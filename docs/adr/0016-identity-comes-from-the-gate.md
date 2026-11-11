# Identity comes from the gate

ZiWoAS has never known who is using it: every page looked the same to everyone. Remembering a
resident's favourites and default view on Schalten (#217) needs a name. Reached from outside,
ZiWoAS already stands behind a sign-in gate that every app of the home shares; it signs the
residents in and tells the app behind it who they are in the header `X-Remote-User`.

ZiWoAS takes the resident from there and has no login of its own.

- **The header counts only from a trusted proxy.** `ZIWOAS_TRUSTED_PROXIES` lists the addresses
  or CIDR ranges of the gate's proxy (`ZiwoasWeb.TrustedProxies`); an invalid entry stops the
  start. From any other peer the header is ignored, so no one on the home network can name
  themselves by sending it.
- **The session carries the name.** `ZiwoasWeb.Plugs.Resident` reads the header on every request
  and keeps the name in the session, which `ZiwoasWeb.Nav` hands to every LiveView as
  `@resident`. A request without the header, or from an untrusted peer, clears it. The session
  is written only when the resident changes.
- **No login inside ZiWoAS.** E-mail sign-in fails when the internet is down, which is when
  someone at home still wants to switch the lights; passwords or passkeys would be a whole
  user machinery for two people, next to the gate that already has one.
- **The home network stays anonymous.** Reached directly, without the gate, ZiWoAS has no
  resident: every device can be switched and Schalten shows the shared view, without favourites
  or a default. A „Wer bist du?“ picker there would be a name anyone can claim.
- **No residents table.** A resident is the login name the gate reports. What ZiWoAS keeps per
  resident is keyed by that name, as plugs are keyed by their id from `ziwoas.yml`.
- **„Abmelden“ is the gate's.** `ZIWOAS_SIGN_OUT_URL` names the gate's sign-in page; signing
  out there ends the session for every app behind the gate. Without it the top bar shows only
  the name.

## Consequences

- A resident renamed at the gate starts without favourites and default view; the old rows stay
  under the old name.
- Anyone who can reach ZiWoAS directly, bypassing the gate, can switch everything, as before.
  The trusted proxy only decides who is named, not who may switch.
