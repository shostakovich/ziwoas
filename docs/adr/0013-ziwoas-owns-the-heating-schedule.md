# ZiWoAS owns the heating schedule, not the Fritz!Box

The FRITZ!DECT 301 thermostats in the Schalten tab (#205) heat by ZiWoAS's time windows. The
Fritz!Box's own weekly program is not used: its heating times are cleared once, and ZiWoAS only
ever writes a target temperature.

The box's program cannot be read or written over AHA, the HTTP interface ZiWoAS speaks: it only
offers the current target (`sethkrtsoll`). A schedule ZiWoAS could not show, edit or reason
about would leave the tab guessing why a heater heats. And what the residents need goes beyond
it anyway: manual heating that ends by itself after four hours, and a switch-off every evening
at 22:00, so that no heater runs all night because someone forgot it.

- **Two states.** A heater heats at its Heiztemperatur (19–22 °C, in half degrees) or rests in
  frost protection: the thermostat switched off (`253`), guarded by its built-in frost protection.
- **One decision.** `Ziwoas.Heating.Decision` folds windows, the latest press, the four-hour cap
  and 22:00 into the state for now and the instant it next changes.
- **One process speaks for the heaters.** `Ziwoas.Fritz.Heaters` polls every thermostat once a
  minute, writes only when the state changes between heating and frost protection, and runs the
  app's commands, so the heaters' own requests reach the box one at a time; the plugs' bridges
  poll it on their own.
- **Turning a thermostat by hand is a press.** A target the box reports that ZiWoAS did not
  write is recorded as a press from the device, at the poll that notices it, unless a command
  is in transit or an open window or boost holds the target. A thermostat found heating for the
  first time counts as such a press.

## Consequences

- A box program left in place overrides ZiWoAS at its own switch times, and each of its changes
  reads as a press by hand; the example config says to clear it.
- A temperature set on the thermostat by hand stays as set until the next change of state, such
  as the four-hour cap; switching to heating, by a window or a press in the app, writes the
  Heiztemperatur. A new Heiztemperatur set in the app while the heater heats is written at once.
- The thermostat applies a new target only when it next wakes, so a press may take a while to
  reach the radiator.
