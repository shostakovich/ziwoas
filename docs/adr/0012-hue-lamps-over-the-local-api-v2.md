# Hue lamps over the bridge's local API v2, behind a vendor-neutral lamp interface

ZiWoAS controls Philips Hue lamps next to the Govee lamps, on the same tiles and lamp page
(#200). It talks to the Hue Bridge on the LAN, never to the Hue cloud, and adds no dependency.

- **Lamps reach their bridge through one interface.** `Ziwoas.Lights.Bridge` is a behaviour with
  four calls: send a command, is the lamp silent, watch for the lamp, stop watching. Each lamp
  records its vendor, and the lamp commands, the power check and the power-up pick the bridge
  by it. Govee and Hue each implement it. The interface covers only how a verb reaches a lamp:
  `Ziwoas.Lights.Commands` still knows Govee's zone lamps (the H60B0's two-zone limit, power as
  the `powerSwitch` zone), which a Hue lamp never is.
- **API v2 over HTTPS, verified.** The bridge's certificate is signed by the Hue root CA
  (`priv/hue/root-bridge.pem`) and names the bridge ID as its common name, without a
  subjectAltName, so OTP's host name check cannot pass. ZiWoAS verifies the chain against that
  CA alone, learns the bridge ID from `/api/0/config` without sending the key, and accepts every
  later connection only from a certificate whose common name is that ID. The ID is learned once
  per start: a reconnect does not ask again, so another bridge at the same address is refused.
- **The event stream is the state.** `/eventstream/clip/v2` pushes every change, from ZiWoAS, the
  Hue app or a dimmer switch. On each (re)connect ZiWoAS opens the stream first and then reads
  the full resource list once, so no change falls between the two. There is no polling. Added
  or deleted lights, devices or Zigbee connections trigger one more full read.
- **A lamp is a light service**, keyed by its ID without hyphens, so a device with two light
  sources, such as the Twilight, is two lamps. Resetting the bridge or re-pairing a lamp makes a
  new lamp.
- **What a lamp can do comes from its light resource**: colour with its gamut, white with its
  mirek range, and its effects, which take the place of Govee's scenes. RGB is converted to xy
  inside the lamp's gamut, kelvin to mirek inside its range.

## Consequences

- The bridge sends nothing while nothing changes, so a dead connection would go unnoticed. A
  stream silent for 10 minutes is dropped and reopened, with the full read that comes with it;
  so is a stream that does not answer within 10 s or buffers more than 1 MB without ending an
  event.
- A stream that ends is reopened after 1 s, doubling to 60 s while it keeps ending within a
  minute.
- An unreachable lamp (its Zigbee connection not `connected`) is shown off, whatever the bridge
  still reports for it.
- Hue rooms, zones, bridge scenes, timed effects (sunrise, sunset) and gradients stay in the Hue
  app; a gradient lamp takes one colour.
