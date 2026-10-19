---
paths:
  - "**/payment*/**"
  - "**/*payment*"
  - "**/billing/**"
  - "**/checkout/**"
  - "**/orders/**"
---

# Payments

- Mobile money only for now (Airtel Money, TNM Mpamba, possibly via an aggregator such as Paychangu).
- States: `pending → paid / failed / expired`. Confirmed by provider callback plus a reconciliation job,
  never by the frontend.
- Money is integer minor units + ISO currency code (MWK now, USD later).
- Store the provider reference and a masked phone number only. Refunds can be a manual-payout state.
