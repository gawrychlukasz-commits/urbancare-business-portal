-- URBANCARE BPL 007: preserve quote originals, revisions, and externally issued PDFs.
-- Run in Supabase SQL Editor after 006_quotes.sql. Safe to rerun.
alter table public.quotes
 add column if not exists source_quote_id uuid references public.quotes(id) on delete restrict,
 add column if not exists original_pdf_path text;

create index if not exists quotes_source_quote_idx on public.quotes(source_quote_id);

-- Restrict modifications to quoted content after leaving Draft. An original
-- PDF can be attached once, but not replaced from the browser.
create or replace function public.protect_quote_history()
returns trigger language plpgsql set search_path=public as $$
begin
 if new.owner_id is distinct from old.owner_id then
   raise exception 'Quote owner cannot change';
 end if;
 if old.status <> 'draft' and (
      new.client_id is distinct from old.client_id
      or new.quote_number is distinct from old.quote_number
      or new.quote_data is distinct from old.quote_data
      or new.image_path is distinct from old.image_path
      or new.source_quote_id is distinct from old.source_quote_id
   ) then raise exception 'Issued quote content cannot be edited; create a revision instead';
 end if;
 if old.original_pdf_path is not null
    and new.original_pdf_path is distinct from old.original_pdf_path then
   raise exception 'Original PDF cannot be replaced';
 end if;
 if new.original_pdf_path is not null and new.original_pdf_path
    is distinct from (new.owner_id::text||'/'||new.id::text||'.pdf') then
   raise exception 'Invalid PDF storage path';
 end if;
 return new;
end $$;
drop trigger if exists protect_quote_history_trigger on public.quotes;
create trigger protect_quote_history_trigger before update on public.quotes
 for each row execute function public.protect_quote_history();

-- Register an external quote, without creating a duplicate quote number.
-- If a matching quote already exists for that client, return its ID for PDF
-- attachment. Do not overwrite its status or recorded quote content.
create or replace function public.register_existing_quote(
 p_client_id uuid,p_quote_number text,p_quote_date date,
 p_title text,p_amount numeric,p_status text
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_owner uuid:=auth.uid(); v_id uuid; v_old public.quotes%rowtype; v_data jsonb;
begin
 if v_owner is null then raise exception 'Sign in first'; end if;
 if p_client_id is null or p_quote_number is null
   or length(btrim(p_quote_number))<1 or length(btrim(p_quote_number))>50
   or p_quote_date is null
   or p_status not in ('sent','approved','declined','cancelled','archived')
   or (p_amount is not null and
       (p_amount<0 or p_amount>99999999.99 or round(p_amount,2)<>p_amount)) then
   raise exception 'Check client, quote number, issue date, status and optional amount';
 end if;
 if not exists(select 1 from public.clients
    where id=p_client_id and owner_id=v_owner) then
   raise exception 'Client does not belong to your account';
 end if;
 v_data=jsonb_build_object('imported',true,
   'qDate',p_quote_date::text,'qTitle',coalesce(p_title,''),
   'qSelected','custom',
   'qCustomTotal',coalesce(p_amount::text,''),
   'qScope','');
 insert into public.quotes(owner_id,client_id,quote_number,status,quote_data)
 values(v_owner,p_client_id,btrim(p_quote_number),p_status,v_data)
 on conflict(owner_id,quote_number) do nothing
 returning id into v_id;
 if v_id is null then
  select * into v_old from public.quotes
   where owner_id=v_owner and quote_number=btrim(p_quote_number);
  if v_old.id is null or v_old.client_id is distinct from p_client_id then
    raise exception 'That quote number belongs to a different client';
  end if;
  if v_old.original_pdf_path is not null then
    raise exception 'This quote already has a saved PDF';
  end if;
  v_id=v_old.id;
 end if;
 return v_id;
end $$;
revoke all on function public.register_existing_quote(uuid,text,date,text,numeric,text) from public,anon;
grant execute on function public.register_existing_quote(uuid,text,date,text,numeric,text) to authenticated;

create or replace function public.attach_original_quote_pdf(p_quote_id uuid,p_path text)
returns void language plpgsql security definer set search_path=public as $$
declare v_owner uuid:=auth.uid(); v_count integer;
begin
 if v_owner is null then raise exception 'Sign in first'; end if;
 if p_path is distinct from (v_owner::text||'/'||p_quote_id::text||'.pdf') then
   raise exception 'Invalid quote PDF path';
 end if;
 update public.quotes set original_pdf_path=p_path
 where id=p_quote_id and owner_id=v_owner and original_pdf_path is null;
 get diagnostics v_count=row_count;
 if v_count<>1 then raise exception 'Quote not found or PDF already attached'; end if;
end $$;
revoke all on function public.attach_original_quote_pdf(uuid,text) from public,anon;
grant execute on function public.attach_original_quote_pdf(uuid,text) to authenticated;

-- Make the original quote PDF private and write-once (10 MB max).
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('quote-pdfs','quote-pdfs',false,10485760,array['application/pdf'])
 on conflict(id) do update set public=false,file_size_limit=10485760,
   allowed_mime_types=array['application/pdf'];

drop policy if exists "Owner reads original quote PDFs" on storage.objects;
drop policy if exists "Owner uploads original quote PDFs" on storage.objects;
create policy "Owner reads original quote PDFs" on storage.objects
 for select to authenticated using(
  bucket_id='quote-pdfs'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and exists(select 1 from public.quotes q
    where q.owner_id=(select auth.uid())
    and name=q.owner_id::text||'/'||q.id::text||'.pdf')
 );
create policy "Owner uploads original quote PDFs" on storage.objects
 for insert to authenticated with check(
  bucket_id='quote-pdfs'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and exists(select 1 from public.quotes q
    where q.owner_id=(select auth.uid()) and q.original_pdf_path is null
    and name=q.owner_id::text||'/'||q.id::text||'.pdf')
 );
-- No update or delete policy: quoted original documents are preserved.
