# Savings count self-consumption only; exported energy is worth nothing

Savings used to be the energy the producer plug delivered, priced at the household's electricity
price — as if every kilowatt-hour had replaced a bought one. It hadn't: whatever the measured
consumers did not take at that moment went to unmeasured loads or left the house, and nothing
is paid for what leaves. Savings are therefore **self-consumption × electricity price**, where
self-consumption is the per-bucket overlap of production and measured consumption — a lower
bound that can be proven, not an estimate of what was probably used.

The alternative, crediting exported energy at a feed-in price, was rejected twice over: there is
no feed-in contract, so the price is zero, and there is no whole-house meter, so the quantity
cannot be measured either (ADR-0002). Should either change, the price side is a new electricity
price kind; the quantity side needs a meter first.

## Consequences

- Every "Gespart" figure in the product — dashboard, reports, API, ROI view — uses this one
  definition. Numbers are visibly smaller than before, and correct.
- Unmeasured household loads running on solar power are not credited. Adding a consumer plug is
  the only way to make their savings count.
- Savings before **data start** are never estimated, so payback is always reckoned late rather
  than early.
