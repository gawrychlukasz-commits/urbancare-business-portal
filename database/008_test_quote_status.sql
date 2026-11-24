-- URBANCARE BPL 008: TEST quote status, safely separated from issued quotes.
-- Run once in Supabase SQL Editor. Safe to rerun.
alter table public.quotes drop constraint if exists quotes_status_check;
alter table public.quotes add constraint quotes_status_check
 check (status in ('draft','test','sent','approved','declined','cancelled','archived'));

-- TEST can be used for non-issued quotes and returned to Draft.
-- Already issued/approved/declined/cancelled/archived quotes cannot be moved
-- to TEST or Draft, keeping historical signed-off records protected.
create or replace function public.protect_quote_history()
returns trigger language plpgsql set search_path=public as $$
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
 ) then raise exception 'Original quote must belong to the same account'; end if;
 if old.status not in ('draft','test') and (
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
