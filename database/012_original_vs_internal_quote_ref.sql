-- URBANCARE BPL 012: internal quote reference without changing the number printed on the PDF.
-- Run AFTER 011. Safe to rerun. Does not overwrite quote 1808 for Padel Point.
-- BPL: Padel Point 1808. The Cove Dining: internal 1808-COVE; original PDF 1808.
begin;

alter table public.quotes
 add column if not exists original_quote_number text;

comment on column public.quotes.original_quote_number is
  'Number actually printed on the original client-facing quote PDF, when different from the unique BPL quote_number.';

-- Retain all protection from 008, adding a narrow one-time exception for
-- assigning an internal BPL identifier to an unverified, imported quote that
-- was initially registered without a number. Issued content remains protected.
create or replace function public.protect_quote_history()
returns trigger language plpgsql set search_path=public as $$
declare allow_internal_assignment boolean := false;
begin
 if new.owner_id is distinct from old.owner_id then
   raise exception 'Quote owner cannot change';
 end if;

 if old.status not in ('draft','test') and new.status in ('draft','test') then
   raise exception 'Issued quotes cannot return to Draft or TEST; create a revision';
 end if;

 if new.source_quote_id is not null and not exists(
   select 1 from public.quotes parent
   where parent.id=new.source_quote_id and parent.owner_id=new.owner_id
 ) then
   raise exception 'Original quote must belong to the same account';
 end if;

 -- Only a previously unnumbered imported, unverified quote can receive
 -- its first unique internal BPL reference. No changes to client/scope/PDF.
 allow_internal_assignment :=
   old.status not in ('draft','test')
   and old.quote_number is null
   and old.is_verified=false
   and old.quote_data->>'imported'='true'
   and old.original_pdf_path is null
   and new.quote_number is not null
   and length(btrim(new.quote_number)) between 1 and 50
   and new.original_quote_number is not null
   and length(btrim(new.original_quote_number)) between 1 and 50
   and old.original_quote_number is null
   and new.client_id is not distinct from old.client_id
   and new.quote_data is not distinct from old.quote_data
   and new.image_path is not distinct from old.image_path
   and new.source_quote_id is not distinct from old.source_quote_id;

 if old.status not in ('draft','test') and (
      new.client_id is distinct from old.client_id
      or (new.quote_number is distinct from old.quote_number and not allow_internal_assignment)
      or new.quote_data is distinct from old.quote_data
      or new.image_path is distinct from old.image_path
      or new.source_quote_id is distinct from old.source_quote_id
   ) then
   raise exception 'Issued quote content cannot be edited; create a revision instead';
 end if;

 -- The original printed number is retained permanently once documented.
 if old.original_quote_number is not null
    and new.original_quote_number is distinct from old.original_quote_number then
   raise exception 'Original printed quote number cannot be changed';
 end if;
 if old.status not in ('draft','test')
    and new.original_quote_number is distinct from old.original_quote_number
    and not allow_internal_assignment then
   raise exception 'Printed number can only be assigned while importing an unnumbered quote';
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

do $$
declare v_id uuid; v_count integer;
begin
 -- The Cove import from 011 is recognized by a unique, explicit import key.
 select count(*) into v_count from public.quotes q
 join public.clients c on c.id=q.client_id
 where q.quote_data->>'importKey'='cove-walkway-2026-11-23'
   and lower(c.business_name) like '%cove dining%';

 if v_count=1 then
   select q.id into v_id from public.quotes q
   join public.clients c on c.id=q.client_id
   where q.quote_data->>'importKey'='cove-walkway-2026-11-23'
     and lower(c.business_name) like '%cove dining%';

   if exists(select 1 from public.quotes where id=v_id and
      quote_number='1808-COVE' and original_quote_number='1808') then
     raise notice 'The Cove already uses internal 1808-COVE and original 1808; unchanged.';
   elsif exists(select 1 from public.quotes where id=v_id and quote_number is null
       and original_quote_number is null and is_verified=false
       and original_pdf_path is null) then
     if exists(select 1 from public.quotes q1 join public.quotes q2 on q1.owner_id=q2.owner_id
          where q1.id=v_id and q2.quote_number='1808-COVE' and q2.id<>v_id) then
        raise exception '1808-COVE is already used by another quote; review before assigning.';
     end if;
     update public.quotes set quote_number='1808-COVE',
       original_quote_number='1808', updated_at=now() where id=v_id;
     raise notice 'The Cove: internal reference 1808-COVE, original PDF number 1808. Padel Point 1808 unchanged.';
   else
     raise notice 'The Cove has other saved identifiers or an archived PDF. No changes; review manually.';
   end if;
 else
   raise notice 'The Cove import not uniquely identified (matching quotes: %). Run 011 first, or review manually.',v_count;
 end if;
end $$;
commit;
