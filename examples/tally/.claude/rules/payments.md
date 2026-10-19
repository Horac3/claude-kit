---
paths:
  - "**/payment*/**"
  - "**/*payment*"
  - "**/billing/**"
---

# Payments

- Card and bank transfer through a payment provider behind a `PaymentGateway` port.
- States: `pending → paid / failed / expired`. Confirmed by provider webhook plus a reconciliation job,
  never by the frontend. Webhooks are verified by signature and deduplicated by event ID.
- Money is integer minor units + ISO currency code. Never floats.
- Store the provider reference only, never card details. Partial payments are allowed; overpayments become
  client credit.
