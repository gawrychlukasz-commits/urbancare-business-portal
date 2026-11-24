-- URBANCARE BPL: Quotes, status history, and private quote images.
-- Run in URBANCARE-BPL Supabase SQL Editor. Safe to rerun.
create table if not exists public.quotes (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id),
 client_id uuid not null references public.clients(id) on delete restrict,
 quote_number text,
 status text not null default 'draft' check(status in ('draft','sent','approved','declined','cancelled','archived')),
 quote_data jsonb not null default '{}'::jsonb check(jsonb_typeof(quote_data)='object'),
 image_path text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint quote_number_distinct_per_owner unique(owner_id,quote_number)
);
create index if not exists quotes_owner_updated_idx on public.quotes(owner_id,updated_at desc);
alter table public.quotes enable row level security;
drop policy if exists "Owner reads quotes" on public.quotes;
drop policy if exists "Owner creates quotes" on public.quotes;
drop policy if exists "Owner updates quotes" on public.quotes;
drop policy if exists "Owner deletes draft quotes" on public.quotes;
create policy "Owner reads quotes" on public.quotes for select to authenticated using(owner_id=(select auth.uid()));
create policy "Owner creates quotes" on public.quotes for insert to authenticated
 with check(owner_id=(select auth.uid()) and exists(
   select 1 from public.clients c where c.id=client_id and c.owner_id=(select auth.uid())
 ));
create policy "Owner updates quotes" on public.quotes for update to authenticated
 using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()) and exists(
   select 1 from public.clients c where c.id=client_id and c.owner_id=(select auth.uid())
 ));
-- No hard-delete policy. Cancelling/archiving preserves sent quote history.
grant usage on schema public to authenticated;
grant select,insert,update on public.quotes to authenticated;
revoke delete on public.quotes from authenticated,anon;
-- The image bucket is private. Uploaded images must belong to an existing quote.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values ('quote-images','quote-images',false,10485760,array['image/jpeg','image/png','image/webp'])
 on conflict (id) do update
  set public=false,file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "Owner reads quote images" on storage.objects;
drop policy if exists "Owner uploads quote images" on storage.objects;
drop policy if exists "Owner replaces quote images" on storage.objects;
create policy "Owner reads quote images" on storage.objects
 for select to authenticated using(
   bucket_id='quote-images' and
   (storage.foldername(name))[1]=(select auth.uid())::text and
   exists(select 1 from public.quotes q where q.owner_id=(select auth.uid())
    and q.id::text=(storage.foldername(name))[2])
 );
create policy "Owner uploads quote images" on storage.objects
 for insert to authenticated with check(
  bucket_id='quote-images' and
  (storage.foldername(name))[1]=(select auth.uid())::text and
  exists(select 1 from public.quotes q where q.owner_id=(select auth.uid())
    and q.id::text=(storage.foldername(name))[2] and q.status='draft')
 );
-- Files are immutable once uploaded. New image uploads get a fresh filename.
-- Quotes approved/sent should not be altered accidentally.
