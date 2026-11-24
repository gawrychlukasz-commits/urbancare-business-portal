-- URBANCARE: invoice history (first small migration)
-- Run this in your URBANCARE-BPL Supabase SQL editor.
-- Keeps previously issued numbers even if an invoice is voided.
create table if not exists public.invoice_history (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id),
 client_id uuid not null references public.clients(id),
 invoice_number text not null,
 issue_date date not null,
 due_date date,
 amount_aud numeric(12,2) not null check (amount_aud >= 0),
 payment_status text not null default 'unpaid'
   check (payment_status in ('unpaid','part_paid','paid')),
 issue_status text not null default 'sent'
   check (issue_status in ('sent','void')),
 notes text,
 created_at timestamptz not null default now(),
 constraint unique_invoice_per_owner unique(owner_id,invoice_number)
);
alter table public.invoice_history enable row level security;
drop policy if exists "Owner can read invoice history" on public.invoice_history;
create policy "Owner can read invoice history" on public.invoice_history
 for select to authenticated using (owner_id=(select auth.uid()));
-- Read-only from the public frontend until audited write endpoints are implemented.
grant usage on schema public to authenticated;
grant select on public.invoice_history to authenticated;
revoke insert,update,delete on public.invoice_history from anon,authenticated;

-- Record your already-sent Padel Point invoice exactly once.
-- The SQL editor runs without auth.uid(), so identify the owner through
-- the existing client row. Stop with an error if client selection is ambiguous.
do $$
declare
  target_client public.clients%rowtype;
  hits integer;
begin
 select count(*) into hits from public.clients
  where upper(btrim(business_name))='PADEL POINT PTY LTD';
 if hits <> 1 then
   raise exception 'Expected exactly one PADEL POINT PTY LTD client, found %. Check duplicates before importing.',hits;
 end if;
 select * into target_client from public.clients
  where upper(btrim(business_name))='PADEL POINT PTY LTD';
 insert into public.invoice_history
 (owner_id,client_id,invoice_number,issue_date,due_date,amount_aud,payment_status,issue_status,notes)
 values(target_client.owner_id,target_client.id,'11126','2026-11-24','2026-12-08',
 680.00,'unpaid','sent','Glass cleaning $600 plus Playtomic access $80. Sent by owner via Outlook. Payment not yet confirmed.')
 on conflict (owner_id,invoice_number) do nothing;
end $$;
-- Note: "unpaid" means payment has not been recorded, not confirmation of non-payment.
