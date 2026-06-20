# Solakon Live Energy Flow Design

## Goal

Build a Home-Assistant-style live energy overview that uses the Solakon One as the authoritative source for current PV/battery output. The existing dashboard energy flow stays in its current location, keeps the existing Solar/Grid/Home logos, and adds a new plush-style battery logo.

The live view shows watts instead of daily kWh values. It also shows the battery state of charge and a signed battery power value where charging is displayed as `+W` and discharging as `-W`.

## Scope

In scope:

- Add Solakon live readings as their own persisted measurement series.
- Read Solakon Modbus values for AC output, PV power, battery power, and battery state of charge.
- Use Solakon AC output instead of the outside Shelly plug for the live energy overview.
- Calculate the live grid value from current home consumption and Solakon AC output.
- Add a battery node to the existing energy flow diagram.
- Show all six connections between Solar, Grid, Home, and Battery.
- Animate flow dots only on paths with current power flow.
- Keep Solakon read-only monitoring separate from optional write control.

Out of scope for this first implementation:

- Replacing historical PV/day charts and reports with Solakon data.
- Removing the outside Shelly plug from the app entirely.
- Adding a true utility-grid meter. The grid value remains calculated, not measured.
- Reworking unrelated dashboard sections.

## Solakon Values

The implementation uses the Solakon Modbus client values already represented in `SolakonClient::State`:

- `active_power_w`: Solakon AC output into the house network, register `39248`.
- `pv_power_w`: sum of Solakon PV string powers.
- `battery_power_w`: raw Solakon battery power, register `39230`.
- `battery_soc`: battery state of charge, register `39424`.

`active_power_w` is the value used for the live Solakon feed into the house network. It is better suited for this view than calculating AC output from PV minus battery power. It is not a true external grid-meter reading.

## Data Model

Add a dedicated `solakon_readings` measurement series. These readings are not stored in the existing Shelly `samples` table because they have different source semantics and fields.

Each reading stores:

- `taken_at`: time of the Modbus read.
- `active_power_w`: Solakon AC output.
- `pv_power_w`: total PV power.
- `battery_power_w`: raw Solakon battery power.
- `battery_soc_pct`: battery state of charge percentage.

The UI battery display power is derived from the stored raw value instead of being persisted separately. The Solakon One's raw sign convention on register `39230` reports **charging as positive** (verified live against the device: `+14 W` while charging, with PV > AC output), which matches the UI convention (charging `+`, discharging `−`), so the raw value is used as-is without inversion.

The model should expose a latest-fresh lookup using the configured stale threshold.

## Job Architecture

Introduce a leading Solakon monitoring job that runs every 30 seconds.

The monitoring job:

- Reads the Solakon state once through Modbus.
- Persists a `solakon_reading`.
- Makes the reading available to the live API/dashboard.
- Never writes to the Solakon.

After a successful read:

- If `control_enabled` is false, the job stops after storing/broadcasting the reading.
- If `control_enabled` is true, the zero-export control path runs immediately using the freshly read state or the persisted reading ID.

The control path must not perform a second Solakon read for the same tick. A failed or invalid monitoring read prevents the control path from running.

The existing zero-export target calculation stays conceptually the same: it still uses current consumer demand, safety margins, and minimum battery SoC rules to decide the target output. The difference is that reading and optional writing are now ordered explicitly.

## Configuration

Replace the single-purpose Solakon enablement behavior with separate monitoring and control flags:

```yml
solakon:
  host: 192.168.x.x
  port: 502
  unit_id: 1
  stale_after_s: 120
  monitoring_enabled: true
  control_enabled: false
```

Meaning:

- `monitoring_enabled: true`: read Solakon values, store them, and use them in the live dashboard.
- `control_enabled: true`: after a successful read, allow the zero-export control path to write to Solakon.
- `monitoring_enabled: false`: perform no Solakon reads and no Solakon writes.

Writes are allowed only when `control_enabled: true` is explicitly set.

The old `enabled` key should be treated as a compatibility fallback during migration for read-only monitoring only. It must not imply write permission. New examples and documentation should use `monitoring_enabled` and `control_enabled`. When both old and new keys are present, the new keys take priority.

## Live API And Calculation

The live API returns a Solakon/energy-flow block based on the latest fresh `solakon_reading` plus current Shelly consumer samples.

Core live values:

- `home_w`: sum of current consumer values, as today.
- `solakon_ac_w`: `active_power_w` from the latest Solakon reading.
- `solar_w`: `pv_power_w` from the latest Solakon reading.
- `battery_soc_pct`: battery state of charge.
- `battery_w`: display battery power, positive while charging and negative while discharging.
- `grid_w`: calculated as `home_w - solakon_ac_w`.

Interpretation:

- `grid_w > 0`: the home is importing that amount from the grid.
- `grid_w < 0`: the Solakon output exceeds known consumption, so the surplus is shown as calculated export.
- `grid_w = 0`: the home is calculated as covered.

The outside Shelly plug is not used as the PV producer in this live energy overview. Existing Shelly consumers remain the source for `home_w`.

## UI Design

The existing live energy overview remains in place on the dashboard.

Nodes:

- Solar at the top, existing logo.
- Grid on the left, existing logo.
- Home on the right, existing logo.
- Battery at the bottom, new plush-style logo.

The diagram always shows all six connections between the four nodes:

- Solar to Home: orange.
- Solar to Grid: violet.
- Solar to Battery: pink.
- Grid to Home: blue.
- Grid to Battery: grey.
- Battery to Home: teal.

The lines stay visible even when no current flow is active. Flow dots animate only on active paths, and their direction follows the current power direction.

Node labels show live watts:

- Solar shows current PV power.
- Grid shows calculated import/export.
- Home shows current consumer demand.
- Battery shows state of charge and signed battery power.

Battery display examples:

- Charging: `84%` and `+50 W`.
- Discharging: `84%` and `-50 W`.

## Error Handling

If there is no fresh Solakon reading:

- Solakon-dependent values show as unavailable.
- Solakon-dependent flow dots stop.
- Existing consumer values can still update from Shelly samples.
- The control path does not run.

If a Solakon read fails or returns invalid required values:

- The failure is logged.
- No `solakon_reading` is persisted for that failed tick.
- No Solakon write is attempted for that tick.

If consumer samples are stale but Solakon is fresh:

- Solakon values can still be displayed.
- `home_w` and calculated `grid_w` should reflect that consumer data is stale or unavailable rather than pretending to be accurate.

## Testing

Add focused tests for:

- Config parsing of `monitoring_enabled`, `control_enabled`, and compatibility fallback behavior, including that old `enabled` does not authorize writes.
- `SolakonReading` freshness lookup and battery display sign conversion.
- Monitoring job persisting a reading without writing when control is disabled.
- Monitoring job invoking the control path only after a successful read and only when control is enabled.
- API response shape and calculated `grid_w`.
- Dashboard behavior for fresh Solakon data, missing Solakon data, battery charging, and battery discharging.

Manual verification should include the dashboard live view with a fresh reading, no fresh reading, positive grid import, calculated export, battery charging, and battery discharging.
