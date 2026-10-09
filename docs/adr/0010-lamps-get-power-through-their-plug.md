# Lamps get power through their plug, never lose it automatically

Some Govee lamps hang on a Shelly plug. With the plug off a lamp is **unpowered**: a LAN command
goes out as UDP and vanishes, so ZiWoAS reported success while nothing happened. Commanding an
unpowered lamp now switches its plug on, waits for the lamp to answer, and only then sends the
command (#176).

- **Unpowered or silent**: the plug's relay is reported off, or the bridge has not heard the lamp
  for three LAN polls. Only a lamp once heard on the LAN can fall silent. Switching off an
  unpowered lamp records it off and leaves the plug alone; a silent one gets the off sent, since
  it may be on and merely quiet.
- **The plug is never switched off by ZiWoAS on the lamp's behalf**, not even when the lamp does
  not answer. Turning a plug off behind a person's back is worse than a lamp left on.
- **The waiting belongs to the server**, one `Lights.PowerUp` process for all lamps, not to the
  page that started it. It also switches the plug, in its own task: leaving the page aborts
  nothing, every page shows the same attempt, and a second tap joins it instead of switching
  again. A plug that does not answer ends the attempt at once.
- **Reachable means heard on the LAN** (a scan or status reply). While a lamp is awaited the
  bridge scans every 2 s instead of every 8. After the first reply the collected commands go
  out, and they are repeated every 5 s until a status reply shows the wanted power, because a
  zone lamp's `powerSwitch` goes through the cloud, which comes up later than the LAN.
- **60 s deadline** from the command that started the attempt. A lamp never heard gives up with a notice; one
  that answered got its commands and ends quietly, even if no status confirmed them yet.
- **Commands during the wait are collected**: the last one per kind wins (colour and white are one
  kind), an off replaces all others, a command after an off turns the lamp on again, and power is
  sent first. An attempt always switches the lamp on unless it was told off. A command that
  arrives after the first delivery goes out with the next reply. A plug that fails after the
  lamp was heard ends nothing: the lamp has power.
- **Only switchable Shelly plugs power lamps**; the switching guard stays as it is. The plug is
  switched with source `:manual`, like any button press.

## Consequences

- An attempt lives in memory: a restart drops it, and the plug stays on. A restarted bridge is
  watched again on the next 5 s tick.
- A lamp the LAN never hears (cloud only) is never reachable by this rule; on a plug that is off
  it times out after 60 s.
- The plug that powers a lamp keeps its own schedule, which knows nothing of the lamp.
