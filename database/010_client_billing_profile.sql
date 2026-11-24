-- URBANCARE BPL 010: complete client billing and operations profile.
-- Run once after 009. Safe to rerun. Does not change existing client data.
alter table public.clients
 add column if not exists legal_billing_entity text,
 add column if not exists trading_name text,
 add column if not exists client_abn text,
 add column if not exists accounts_email text,
 add column if not exists purchase_order_ref text;

-- Keep historic business_name, email, billing_address and site_address unchanged.
-- Blank new fields remain NULL until confirmed in Add/Edit/VERIFY.
comment on column public.clients.legal_billing_entity is 'Legal entity to show on invoice, not assumed from trading name.';
comment on column public.clients.trading_name is 'Trading name used at the location or in correspondence.';
comment on column public.clients.client_abn is 'Australian Business Number; optional and not inferred.';
comment on column public.clients.accounts_email is 'Preferred invoice recipient; falls back to primary contact email.';
comment on column public.clients.purchase_order_ref is 'Customer-provided PO or billing reference, when applicable.';
