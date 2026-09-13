# PROTOTYPE — Sonnenjahr

Throwaway prototype answering: *how should the distribution of PV yield over the calendar
year look, and where does the garden cast shade?* Two variants, switchable with the pill at
the bottom or the arrow keys: **B Sonnenkalender** (day × hour strips inside the sun path) and
**C Schattenkarte** (yield ratio by sun position). A third variant, a week × hour carpet, was
built and rejected.

Not production code: no tests, hard-coded summer time, data baked into a JS file.

## Run

```sh
./export.sh /path/to/copy-of-production.sqlite3   # writes hours.js (gitignored: real data)
open sonnenjahr.html
```

The verdict and the decisions it led to live in the implementation issues; the vocabulary in
`CONTEXT.md` under "Sun".
