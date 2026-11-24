-- URBANCARE BPL 011: quote review / delivery evidence and one-time Tribe quote 1806 intake.
-- Run AFTER 010. Safe to rerun: never overwrites an existing numbered quote.
alter table public.quotes
 add column if not exists is_verified boolean not null default true,
 add column if not exists delivery_method text,
 add column if not exists sent_date date;
comment on column public.quotes.is_verified is 'False = chat/history imported metadata needs owner review; not client approval.';
comment on column public.quotes.delivery_method is 'Email, WhatsApp, in person or other, as reported; not independent proof of delivery.';
comment on column public.quotes.sent_date is 'Actual date sent; distinct from quote issue date. NULL until confirmed.';

-- Import Quote 1806 from the original PDF supplied in chat.
-- Source: dated 7 Nov 2026, 60 days, 5 courts, two separate PRICE OPTIONS.
-- User confirmed the quote was sent over WhatsApp; actual send date not supplied.
-- The original PDF IS NOT transferred by SQL and must not be represented as archived.
do $$
declare
 v_client public.clients%rowtype;
 v_count integer;
begin
 select count(*) into v_count from public.clients
 where lower(btrim(business_name))='tribe padel wellness group pty ltd';
 if v_count<>1 then
   raise notice 'Tribe quote skipped: expected exactly one matching client, found %. Existing records untouched.',v_count;
 else
   select * into v_client from public.clients
   where lower(btrim(business_name))='tribe padel wellness group pty ltd';
   insert into public.quotes(owner_id,client_id,quote_number,status,quote_data,is_verified,delivery_method,sent_date)
   values (
     v_client.owner_id,v_client.id,'1806','sent',
     jsonb_build_object(
       'imported',true,'importSource','ChatGPT attachment: URBANCARE_Quote_1806_Tribe_Padel 1(2).pdf',
       'qNumber','1806','qDate','2026-11-07','qValidity','60',
       'qTitle','Padel Court Glass Cleaning',
       'qScope','Five padel courts: glass highlighted in green on the original quote illustration.',
       'qMethod','Cleaning method: TBC; frequency: TBC',
       'qExclusions','Frames, tracks, fencing, nets, court surfaces, paving, hard-water stains, mineral deposits, paint, glue, cement and restoration.',
       'qOption1','Internal glass only — 5 courts × $100','qPrice1','500',
       'qOption2','Internal and external glass — 5 courts × $150','qPrice2','750',
       'qSelected','1','qCustomTotal','',
       'qArrangements','Client to provide site access and water. Parking/unloading: arranged. Proposed date, working hours, expected duration: TBC. Payment by bank transfer on invoice. Weather may affect booking; extra work agreed in advance.',
       'originalContact','Mateo Primon | 0493 178 460 | Email TBC',
       'originalBillingEntity','TBC',
       'sourceQuoteNote','Source PDF says DRAFT — outstanding details to confirm. User later confirmed this quote was sent via WhatsApp. Acceptance not confirmed.',
       'originalPdfPending',true
     ),false,'whatsapp',null
   )
   on conflict (owner_id,quote_number) do nothing;
   if found then
     raise notice 'Quote 1806 imported for Tribe: SENT / WhatsApp / NEEDS VERIFICATION. Original PDF still needs secure storage.';
   else
     raise notice 'Quote 1806 already exists: no changes made.';
   end if;
 end if;
end $$;

-- Additional quotes confirmed from URBANCARE Outlook Sent correspondence.
-- 1807 North Rocks: original offer dated 16 Nov, $150/court internal or
-- $200/court both sides, six indoor courts; customer reported existing cleaner.
-- 1808 Padel Point: email dated 19 Nov, $400 internal-only or $600 both sides,
-- four courts; subsequent trial completed (not a separate quote).
-- The Cove Dining: sent to Mirko 23 Nov, approx. 420 m2 pressure cleaning,
-- $2,500. Quote number has NOT been confirmed, so leave quote_number NULL.
-- These are metadata-only until user supplies and verifies the original PDFs.
do $$
declare v_c public.clients%rowtype; v_n integer; v_inserted integer:=0;
begin
 select count(*) into v_n from public.clients
 where lower(btrim(business_name)) like '%padel point%';
 if v_n=1 then
  select * into v_c from public.clients where lower(btrim(business_name)) like '%padel point%';
  insert into public.quotes(owner_id,client_id,quote_number,status,quote_data,is_verified,delivery_method,sent_date)
  values(v_c.owner_id,v_c.id,'1808','sent',jsonb_build_object(
   'imported',true,'importSource','URBANCARE Outlook sent quote 19 Nov 2026','qNumber','1808',
   'qDate','2026-11-19','qTitle','Padel Court Glass Cleaning',
   'qScope','Four padel courts; glass cleaning only',
   'qOption1','Internal glass only — four courts × $100','qPrice1','400',
   'qOption2','Internal and external glass — four courts × $150','qPrice2','600',
   'qSelected','1','qCustomTotal','',
   'sourceQuoteNote','Sent quote via email; separate steel cage cleaning was not included. Original PDF pending.',
   'originalPdfPending',true
  ),false,'email','2026-11-19')
  on conflict(owner_id,quote_number) do nothing;
  if found then raise notice 'Staged 1808 Padel Point'; else raise notice '1808 already exists: unchanged'; end if;
 else raise notice 'Padel Point skipped: % name matches',v_n; end if;

 select count(*) into v_n from public.clients
 where lower(btrim(business_name)) like '%north rocks%padel%'
 or lower(btrim(business_name)) like '%padel%north rocks%';
 if v_n=1 then
  select * into v_c from public.clients
  where lower(btrim(business_name)) like '%north rocks%padel%'
  or lower(btrim(business_name)) like '%padel%north rocks%';
  insert into public.quotes(owner_id,client_id,quote_number,status,quote_data,is_verified,delivery_method,sent_date)
  values(v_c.owner_id,v_c.id,'1807','declined',jsonb_build_object(
   'imported',true,'importSource','URBANCARE Outlook sent quote 16 Nov 2026',
   'qNumber','1807','qDate','2026-11-16','qTitle','Pre-event Padel Court Glass Cleaning',
   'qScope','Six indoor padel courts at North Rocks before the Australian Padel Tour Finals (2–6 December 2026).',
   'qOption1','Internal glass only — six courts × $150','qPrice1','900',
   'qOption2','Internal and external glass — six courts × $200','qPrice2','1200',
   'qSelected','1','qCustomTotal','',
   'sourceQuoteNote','Client replied that they already had a cleaner at a better price. Possible quote-number reuse with an older test email: check original PDF and existing register.',
   'originalPdfPending',true
  ),false,'email','2026-11-16')
  on conflict(owner_id,quote_number) do nothing;
  if found then raise notice 'Staged 1807 North Rocks'; else raise notice '1807 already exists: unchanged; check conflicting test history'; end if;
 else raise notice 'North Rocks skipped: % name matches (client must exist first)',v_n; end if;

 select count(*) into v_n from public.clients
 where lower(btrim(business_name)) like '%cove dining%';
 if v_n=1 then
  select * into v_c from public.clients where lower(btrim(business_name)) like '%cove dining%';
  if not exists(select 1 from public.quotes q where q.owner_id=v_c.owner_id
    and q.client_id=v_c.id and (q.quote_data->>'importKey')='cove-walkway-2026-11-23') then
   insert into public.quotes(owner_id,client_id,quote_number,status,quote_data,is_verified,delivery_method,sent_date)
   values(v_c.owner_id,v_c.id,null,'sent',jsonb_build_object(
     'imported',true,'importKey','cove-walkway-2026-11-23',
     'importSource','URBANCARE Outlook sent price 23 Nov 2026',
     'qDate','2026-11-23','qTitle','External Walkways and Entrance Steps Pressure Cleaning',
     'qScope','High-pressure cleaning of approximately 420 m² of external walkways and entrance steps.',
     'qSelected','custom','qCustomTotal','2500',
     'qArrangements','Mirko offered to forward the quote to the property management team. Clean-walkway image was a sample, not a guaranteed outcome.',
     'sourceQuoteNote','Actual original PDF number unknown; do not assign 1808 because Padel Point uses it.',
     'originalPdfPending',true
   ),false,'email','2026-11-23');
   raise notice 'Staged Cove Dining with number TBC';
  else raise notice 'Cove already staged: unchanged'; end if;
 else raise notice 'Cove Dining skipped: % name matches',v_n; end if;
end $$;
