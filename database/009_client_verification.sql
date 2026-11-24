-- URBANCARE BPL 009: verification workflow for clients imported from prior history.
-- Existing records are treated as verified until explicitly marked for review.
alter table public.clients
 add column if not exists is_verified boolean not null default true;
comment on column public.clients.is_verified is
 'False when a client was added from prior conversation/history and details must be verified in BPL.';

-- Verification is owner-editable through existing client RLS; no new privileges.
