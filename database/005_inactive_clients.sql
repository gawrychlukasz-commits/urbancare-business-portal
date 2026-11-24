-- URBANCARE BPL: active/inactive client directory and guarded permanent deletion
-- Run in Supabase SQL Editor. Safe to rerun.
alter table public.clients
 add column if not exists is_active boolean not null default true;

-- Only authenticated owners can delete an INACTIVE client with no BPL financial links.
-- Other database foreign keys also block deletion if future dependent rows exist.
-- Do not cascade-delete invoice records, historical drafts or client documents.
create or replace function public.delete_inactive_client(p_client_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare v_owner uuid := auth.uid();
begin
 if v_owner is null then raise exception 'Sign in first'; end if;
 if not exists (
  select 1 from public.clients
  where id=p_client_id and owner_id=v_owner and is_active=false
 ) then raise exception 'Client is not in your inactive directory'; end if;
 if exists (select 1 from public.invoice_history
           where client_id=p_client_id and owner_id=v_owner) then
   raise exception 'Cannot delete: this client has issued invoice history. Keep the inactive record.';
 end if;
 if exists (select 1 from public.invoice_drafts
           where client_id=p_client_id and owner_id=v_owner) then
   raise exception 'Cannot delete: this client has saved invoice drafts. Keep the inactive record.';
 end if;
 delete from public.clients
 where id=p_client_id and owner_id=v_owner and is_active=false;
 if not found then raise exception 'Client not found'; end if;
end $$;

revoke all on function public.delete_inactive_client(uuid) from public,anon;
grant execute on function public.delete_inactive_client(uuid) to authenticated;
grant select,update on public.clients to authenticated;
-- NOTE: Other systems (such as reports.urbancare.au) are not synchronised.
-- Before permanent deletion, manually ensure no unlinked reports or documents
-- need the client identity. No existing invoice will be erased by this function.
