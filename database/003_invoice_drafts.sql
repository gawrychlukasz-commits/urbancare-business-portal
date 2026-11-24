-- URBANCARE BPL — editable invoice drafts, separate from issued invoice history.
-- Run in Supabase SQL Editor. Safe to rerun.
create table if not exists public.invoice_drafts (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id),
 client_id uuid references public.clients(id) on delete set null,
 draft_data jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint invoice_draft_json_object check (jsonb_typeof(draft_data)='object')
);
create index if not exists invoice_drafts_owner_updated_idx
 on public.invoice_drafts(owner_id,updated_at desc);
alter table public.invoice_drafts enable row level security;
drop policy if exists "Owner reads own invoice drafts" on public.invoice_drafts;
drop policy if exists "Owner creates own invoice drafts" on public.invoice_drafts;
drop policy if exists "Owner updates own invoice drafts" on public.invoice_drafts;
drop policy if exists "Owner deletes own invoice drafts" on public.invoice_drafts;
create policy "Owner reads own invoice drafts" on public.invoice_drafts
 for select to authenticated using(owner_id=(select auth.uid()));
create policy "Owner creates own invoice drafts" on public.invoice_drafts
 for insert to authenticated with check(
   owner_id=(select auth.uid()) and
   (client_id is null or exists(select 1 from public.clients c
      where c.id=client_id and c.owner_id=(select auth.uid())))
 );
create policy "Owner updates own invoice drafts" on public.invoice_drafts
 for update to authenticated using(owner_id=(select auth.uid()))
 with check(
   owner_id=(select auth.uid()) and
   (client_id is null or exists(select 1 from public.clients c
      where c.id=client_id and c.owner_id=(select auth.uid())))
 );
create policy "Owner deletes own invoice drafts" on public.invoice_drafts
 for delete to authenticated using(owner_id=(select auth.uid()));
grant usage on schema public to authenticated;
grant select,insert,update,delete on public.invoice_drafts to authenticated;
revoke all on public.invoice_drafts from anon;
-- Important: draft records are not issued invoices. The invoice_history table
-- remains read-only and number 11126 is already recorded as sent.
