# What the plant cost and what power costs live in the database, not in ziwoas.yml

Every other setting in this app lives in `config/ziwoas.yml`: devices, location, credentials —
things the operator sets up once while building the system, by hand, next to the server. The
cost items and the electricity price are a different kind of thing. They are maintained from
inside the app while it runs, they accumulate (a repair two years in, a price change), and each
carries a date that the savings calculation reads back. That makes them domain records with
their own tables and their own page, like the switch times and the lights, not configuration.

The alternative was a list under a new YAML key. It was rejected because it would put the one
setting that changes most often behind an SSH session and a restart, and because a validity date
per entry is a record, not a key. The existing `electricity_price_eur_per_kwh` key is refused by
name after this change (ADR-0003 rewrote what it was used for anyway), the way the retired
`timezone` and `weather` keys are: a config that silently means something else than it says is
worse than one that refuses to boot.

## Consequences

- Deploying this change means running the migration first — it carries the YAML price over as
  the first electricity price — and only then removing the key from `config/ziwoas.yml`.
- `ConfigLoader::Config` no longer carries a price, so nothing outside the Economics seam can
  price energy by accident.
- Savings are unknown, not zero, while no price is on record. Every display shows an em dash
  rather than a free kilowatt-hour.
