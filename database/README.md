# URBANCARE Business Portal — Database integration (development)

This is a **draft foundation**, not a production database migration. Do not run `001_foundation_DRAFT.sql` against a live project until the outstanding security tasks are completed.

## Current state
- `bpl.urbancare.au` is a public GitHub Pages frontend.
- Existing client names are illustrative and the invoice form stores a single draft in the current browser.
- Reports at `reports.urbancare.au` use browser IndexedDB for reports and localStorage for the client directory.
- Neither website is connected to the proposed database. Outlook drafting presently works through an authorised ChatGPT connector, **not from the website**.

## Desired relationships
One client -> many jobs; one job -> accepted quote, site reports, invoices; invoice -> multiple line items and payments.

## Numbering
Invoice numbering format: `<monthly sequence><MM><YY>`, e.g. `11126`, `21126`, `11226`. Assign atomically at issue time; draft IDs must use a separate UUID. An issued number must remain in the ledger even if voided.

**Historical migration checkpoint:** User reports invoice **11126** was sent to Padel Point on **24 November 2026**, for **AUD 680**. This is user-reported and must be verified from the final approved PDF before importing; it must not be reused. Do not seed any live counter until the owner identity is established.

## First production milestones
1. Create Supabase project and one private owner account; turn off open self-registration.
2. Review and harden RLS, foreign-key tenancy, invoice immutability, storage policies, and service-role separation. Then run approved migrations.
3. Build a **read-only import preview** from exported browser backup JSON; inspect duplicates before import.
4. Connect a shared client picker and job history to both websites.
5. Add invoice creation with immutable issue numbers, approval controls and manual payment status.
6. Use a secure backend with delegated Microsoft Graph credentials to create **Outlook drafts with attached final PDFs**; require an explicit owner click to send outside the website.
7. Introduce backups, audit history, and an owner-only login before using real customer/bank information.

## Security boundary
GitHub Pages code is public and cannot safely hold database service keys, bank details, Outlook OAuth secrets, or user passwords. The public Supabase project URL and publishable key may be included in frontend code **only after** reviewed Row Level Security is deployed. Never add the Supabase service role key or refresh tokens to repository files.
