# Shelly plugs connect to ZiWoAS over their outbound websocket

Shelly plugs used to talk MQTT through a Mosquitto broker: status on
`<prefix>/<plug>/status/switch:0`, commands as a bare `on`/`off` on `…/command/switch:0`, QoS 0.
After Fritz and Govee left MQTT, the broker served only the Shellys. Gen2+ Shellys can instead
open a websocket to a server themselves (the `Ws` component) and speak their JSON-RPC over it.
ZiWoAS now accepts those connections and the broker, Tortoise311 and the `mqtt:` config are gone.

- **Own port.** A second Bandit listener on `SHELLY_PORT` (3001 in production) serves only the
  Shellys, so the IoT VLAN's firewall rule replaces the old one for 1883 and the VLAN never
  reaches the web UI.
- **The path names the plug.** Each Shelly connects to `ws://<host>:<SHELLY_PORT>/shelly/<plug id>`;
  no device id goes into `ziwoas.yml`. Unknown plug ids get a 404.
- **One process per plug** (`Ziwoas.Shelly.Connection`): it keeps the `switch:0` status (full
  status on connect, `NotifyStatus` deltas merged in) and feeds `Plugs.Ingest` like the Fritz
  bridge does. The newest connection of a plug wins.
- **Switching is a call.** `Switch.Set` goes over the plug's socket and waits for the answer; a
  command counts, and its relay state is stored, only once the plug confirmed it. Without a
  connection switching fails at once.

## Consequences

- Shellys need firmware with outbound websocket support (all Gen2+), and each one is set up once:
  outbound websocket on, MQTT off.
- The device does not authenticate on this channel. Whoever reaches the Shelly port can report
  for any plug; the firewall is the protection.
- A plug whose network drops keeps its stale socket until the 30 s ping goes unanswered and the
  75 s idle timeout closes it; a reconnect replaces it sooner.
