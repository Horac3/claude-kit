---
paths:
  - "packages/domain/**/invoice*/**"
  - "packages/domain/**/*invoice*"
  - "packages/pdf/**"
  - "apps/**/*invoice*"
---

# Invoices (test this first)

- States: `draft → issued → partially_paid / paid / void`. Only drafts can be edited.
- Issuing assigns the next number in the account's sequence (e.g. `2026-0042`) inside a transaction.
  Numbers are never reused or skipped, even if issuing fails later.
- An issued invoice stores its rendered totals and line items; never recompute them from current rates.
- Tax is computed per line, rounded half-even to minor units, then summed. Test with awkward rates.
- Corrections are credit notes that reference the original invoice. Voiding keeps the number.
- The PDF is rendered from the stored invoice version, so re-rendering produces the same document.
