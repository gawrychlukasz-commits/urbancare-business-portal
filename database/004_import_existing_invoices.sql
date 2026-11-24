-- URBANCARE BPL: import already-issued invoice PDFs.
-- Run once in Supabase SQL Editor (safe to rerun).
-- Never place PDFs in the public GitHub repository.
alter table public.invoice_history
 add column if not exists pdf_path text;

-- This RPC creates a sent invoice record, or returns the existing invoice id
-- without altering any of its issued information. Concurrent calls are protected
-- by the existing unique(owner_id, invoice_number) constraint.
create or replace function public.register_manual_invoice(
 p_client_id uuid, p_invoice_number text, p_issue_date date, p_amount_aud numeric
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_owner uuid:=auth.uid(); v_id uuid; v_client_owner uuid;
begin
 if v_owner is null then raise exception 'Sign in first'; end if;
 if p_client_id is null or p_invoice_number is null or
    length(btrim(p_invoice_number))=0 or length(btrim(p_invoice_number))>50 or
    p_issue_date is null or p_amount_aud is null or
    p_amount_aud<0 or p_amount_aud>99999999.99 or
    round(p_amount_aud,2)<>p_amount_aud then
   raise exception 'Check the client, invoice number, issue date and total';
 end if;
 select owner_id into v_client_owner from public.clients where id=p_client_id;
 if v_client_owner is distinct from v_owner then
   raise exception 'Client not found in your account';
 end if;
 insert into public.invoice_history
   (owner_id,client_id,invoice_number,issue_date,amount_aud,
    payment_status,issue_status,notes)
 values(v_owner,p_client_id,btrim(p_invoice_number),p_issue_date,p_amount_aud,
   'unconfirmed','sent','Imported existing invoice (manually sent)')
 on conflict(owner_id,invoice_number) do nothing
 returning id into v_id;
 if v_id is null then
   select id into v_id from public.invoice_history
   where owner_id=v_owner and invoice_number=btrim(p_invoice_number);
 end if;
 return v_id;
end $$;
revoke all on function public.register_manual_invoice(uuid,text,date,numeric) from public,anon;
grant execute on function public.register_manual_invoice(uuid,text,date,numeric) to authenticated;

-- Attach PDFs only to an owner's issued invoice, without changing invoice terms.
create or replace function public.attach_manual_invoice_pdf(
 p_invoice_id uuid, p_pdf_path text
) returns void
language plpgsql security definer set search_path=public
as $$
declare v_owner uuid:=auth.uid(); v_changed integer;
begin
 if v_owner is null then raise exception 'Sign in first'; end if;
 if p_pdf_path is distinct from (v_owner::text||'/'||p_invoice_id::text||'.pdf')
 then raise exception 'Unexpected invoice PDF path'; end if;
 update public.invoice_history set pdf_path=p_pdf_path
 where id=p_invoice_id and owner_id=v_owner and issue_status='sent'
   and (pdf_path is null or pdf_path=p_pdf_path);
 get diagnostics v_changed=row_count;
 if v_changed<>1 then raise exception 'Invoice not found or PDF already attached'; end if;
end $$;
revoke all on function public.attach_manual_invoice_pdf(uuid,text) from public,anon;
grant execute on function public.attach_manual_invoice_pdf(uuid,text) to authenticated;

-- Private bucket, limited to PDFs (max 10 MB).
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('invoice-pdfs','invoice-pdfs',false,10485760,array['application/pdf'])
on conflict(id) do update
 set public=false,file_size_limit=10485760,allowed_mime_types=array['application/pdf'];

-- Restrict storage paths to owner UUID / invoice UUID.pdf.
drop policy if exists "Owner reads own invoice PDFs" on storage.objects;
drop policy if exists "Owner uploads own issued invoice PDFs" on storage.objects;
create policy "Owner reads own invoice PDFs" on storage.objects
 for select to authenticated using(
 bucket_id='invoice-pdfs'
 and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists(select 1 from public.invoice_history i
   where i.owner_id=(select auth.uid()) and
   name=i.owner_id::text||'/'||i.id::text||'.pdf')
);
create policy "Owner uploads own issued invoice PDFs" on storage.objects
 for insert to authenticated with check(
 bucket_id='invoice-pdfs'
 and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists(select 1 from public.invoice_history i
   where i.owner_id=(select auth.uid()) and i.issue_status='sent'
   and name=i.owner_id::text||'/'||i.id::text||'.pdf'
   and i.pdf_path is null)
);
-- No update/delete policy: already-uploaded invoices cannot be replaced from the web app.
-- Existing invoice_history RLS remains read-only for browser users.
