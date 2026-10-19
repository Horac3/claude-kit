---
paths:
  - "packages/domain/**/retention/**"
  - "packages/domain/**/*retention*"
  - "packages/domain/**/*purge*"
  - "apps/**/*purge*"
  - "apps/**/*retention*"
  - "packages/database/**"
---

# Retention (a promise to users — test this first)

- Content (photos, derivatives, text, document, exported PDFs, project title) is ephemeral.
  Accounts, orders, payments, refunds, discounts, consent records persist.
- Draft: purged after 30 days idle (since last edit). Extensions allowed; hard cap about 90 days.
- Delivered: fixed 7-day window starting when export succeeds AND the email is accepted.
  One free 7-day extension. Hard cap 30 days from payment.
- `purge_at` is stored, not derived; recompute on state changes. Holds (refund, dispute, print order) pause it.
- Purge order: close the project under its row lock (re-check due and no hold; null title, document and
  version documents; stamp `purged_at`) → abort open uploads → delete every object under `projects/{id}/`
  → verify the prefix is empty → purge-ledger row → confirmation email. Closing first means an edit or
  upload cannot race the storage delete; the ledger row, not `purged_at`, marks a complete purge.
  Every step is safe to repeat.
- Strip EXIF on upload. Downscale originals to print size (deliberate exception to "originals never modified").
- Per-project encryption keys, deleted at purge.
- Email a lightweight keepsake PDF only to a verified address; never purge before delivery succeeds.
