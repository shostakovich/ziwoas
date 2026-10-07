# Shelly plugs connect to ZiWoAS over their outbound websocket

After Fritz and Govee left MQTT, the Mosquitto broker served only the Shellys. Gen2+ Shellys can
open a websocket to a server themselves and speak JSON-RPC over it, so ZiWoAS accepts those
connections and drops the broker.

- **Own port** (`SHELLY_PORT`): the IoT VLAN reaches the Shellys' listener, never the web UI.
- **The path names the plug** (`/shelly/<plug id>`): no device id in `ziwoas.yml`.
- **A switch counts only once the plug confirmed it**: `Switch.Set` waits for the answer; without a
  connection it fails at once.

## Consequences

- Each Shelly needs Gen2+ firmware and a one-time setup: outbound websocket on, MQTT off.
- The device does not authenticate on this channel; the firewall is the protection.
- A plug whose network drops keeps its stale socket until the 30 s ping goes unanswered and the
  75 s idle timeout closes it; a reconnect replaces it sooner.
- If `Switch.Set` reaches the plug but its answer is lost or later than 5 s, the switch counts as
  failed and no command is logged, so a schedule edge may override that manual switch.
