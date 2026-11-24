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
