-- URBANCARE Business Portal — owner-only database foundation
-- DEVELOPMENT ONLY: do not run until Supabase project & owner account are set up.
-- Server-side invoice numbering and storage are required before real invoicing.

create extension if not exists pgcrypto;

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  business_name text not null,
  billing_name text,
  abn text,
  contact_name text,
  email text,
  phone text,
  billing_address text,
  site_address text,
  internal_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clients_business_name_nonempty check (length(trim(business_name)) > 0)
);

create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  client_id uuid not null references public.clients(id),
  service_title text not null,
  service_date date,
  status text not null default 'planned'
    check (status in ('planned','scheduled','in_progress','completed','cancelled')),
  site_address text,
  description text,
  agreed_total numeric(12,2),
  quote_reference text,
  created_at timestamptz not null default now()
);

create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  client_id uuid not null references public.clients(id),
  job_id uuid references public.jobs(id),
  quote_number text,
  status text not null default 'draft'
    check (status in ('draft','issued','accepted','declined','expired')),
  amount numeric(12,2) check (amount is null or amount >= 0),
  issued_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.service_reports (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  client_id uuid not null references public.clients(id),
  job_id uuid references public.jobs(id),
  report_number text,
  report_type text,
  report_date date,
  report_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  client_id uuid not null references public.clients(id),
  job_id uuid references public.jobs(id),
  report_id uuid references public.service_reports(id),
  invoice_number text,
  status text not null default 'draft'
    check (status in ('draft','issued','part_paid','paid','void')),
  issue_date date,
  due_date date,
  notes text,
  currency text not null default 'AUD' check (currency = 'AUD'),
  total numeric(12,2) not null default 0 check (total >= 0),
  gst_amount numeric(12,2) not null default 0 check (gst_amount >= 0),
  issued_at timestamptz,
  created_at timestamptz not null default now(),
  constraint valid_issued_invoice check (
     (status = 'draft' and invoice_number is null and issued_at is null)
     or
     (status <> 'draft' and invoice_number is not null and issued_at is not null)
  )
);
create unique index if not exists invoices_unique_owner_number
  on public.invoices(owner_id,invoice_number) where invoice_number is not null;

create table if not exists public.invoice_lines (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  position integer not null default 1,
  description text not null,
  quantity numeric(12,2) not null check (quantity >= 0),
  unit_price numeric(12,2) not null check (unit_price >= 0)
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  invoice_id uuid not null references public.invoices(id),
  paid_on date not null,
  amount numeric(12,2) not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now()
);

-- Counter is private; increment only through RPC.
create table if not exists public.invoice_counters (
  owner_id uuid not null,
  year_number integer not null,
  month_number integer not null check (month_number between 1 and 12),
  last_sequence integer not null default 0 check (last_sequence >= 0),
  primary key(owner_id, year_number, month_number)
);

-- All records require authentication. Separate users cannot see each other's records.
do $block$
declare t text;
begin
  foreach t in array array['clients','jobs','quotes','service_reports','invoices','invoice_lines','payments','invoice_counters']
  loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists owner_only on public.%I',t);
    execute format('create policy owner_only on public.%I for all to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))',t);
  end loop;
end $block$;

-- Match linked client/owner IDs before production: this prevents cross-client association
-- by a user who owns multiple clients. App must validate references server-side or via triggers.

-- Issue invoice transactionally: generates monthly sequence at the moment of issue.
-- New status is 'issued' rather than 'paid'; payment requires independent confirmation.
create or replace function public.issue_invoice(p_invoice_id uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_invoice public.invoices%rowtype;
  v_date date := (now() at time zone 'Australia/Sydney')::date;
  v_year int := extract(year from v_date)::int;
  v_month int := extract(month from v_date)::int;
  v_seq int;
  v_no text;
begin
  if v_uid is null then raise exception 'Login required'; end if;
  select * into v_invoice from public.invoices
    where id=p_invoice_id and owner_id=v_uid for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_invoice.status <> 'draft' then raise exception 'Invoice has already been issued'; end if;
  if v_invoice.total < 0 then raise exception 'Invalid invoice total'; end if;
  insert into public.invoice_counters(owner_id,year_number,month_number,last_sequence)
    values(v_uid,v_year,v_month,1)
    on conflict (owner_id,year_number,month_number)
    do update set last_sequence=public.invoice_counters.last_sequence+1
    returning last_sequence into v_seq;
  v_no := v_seq::text || lpad(v_month::text,2,'0') || right(v_year::text,2);
  update public.invoices
    set status='issued', invoice_number=v_no, issue_date=v_date,
        issued_at=now()
    where id=p_invoice_id and owner_id=v_uid;
  return v_no;
end;
$$;
revoke all on function public.issue_invoice(uuid) from public, anon;
grant execute on function public.issue_invoice(uuid) to authenticated;

-- TODO before production:
-- 1. Privileged backend/API for Outlook drafts and approved PDF storage (never in GitHub).
-- 2. Explicit user onboarding / restricted signups and proper ownership checks on all FK relationships.
-- 3. Restrict direct UPDATE of issued invoice_number/status and counter writes with privileges/RPC.
-- 4. Add storage buckets with owner-scoped access policies and backup/recovery.
-- 5. After owner signup, migrate *verified* already-sent invoice 11126 and seed Nov 2026
--    sequence to 1 (never generate 11126 again). Do not seed until owner ID exists.
