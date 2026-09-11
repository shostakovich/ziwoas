# ADR 0002: Solakon load following and full-battery surplus

## Status

Accepted

## Context

The zero-export controller sees only configured consumer plugs, not the whole-house grid flow.
Its former 30-minute median cap suppressed short high loads, but also clipped sustained small
increases such as a refrigerator. Production data from 4–6 September 2026 showed a modeled
89.43% autarky with that cap, while a 200 W per 30-second rise limit modeled 98.87%.

At 100% battery SoC the inverter also curtails PV, so reported PV can fall to zero while solar
energy is still available. Seven observed full-charge transitions then changed from charging to
about 58–69 W of battery discharge. Reported PV cannot be used as the exit signal once curtailment
has started.

## Decision

Normal control follows fresh measured consumption, falling back to the 24-hour guaranteed floor
when live measurements are unavailable. Output rises by at most 200 W per 30-second tick and falls
to a lower measured load on the next tick. All output remains capped at 800 W and by the existing
thermal ceiling.

At 99% SoC or above, battery charging above 15 W enters surplus control. Surplus control adjusts
the last applied target from battery power: charging raises it by at most 200 W per tick;
discharging lowers it by at most 300 W. A ±15 W deadband prevents noise from moving the target.
The normal load-following target remains the lower bound, so measured consumption retains first
priority. Two discharging ticks at that lower bound confirm that solar surplus has ended.

At 100% SoC with reported PV below 50 W, the controller may add one 50 W probe for one successful
tick. Continued battery discharge rejects the probe. The controller does not probe again until
SoC falls below 99% or visible charging proves that surplus has returned. This limits a failed
probe to about 0.4 Wh at the 30-second control interval.

Low-SoC and thermal protection take precedence over every surplus state. A stored decision expires
with the inverter's 150-second remote-control watchdog. Only successfully written targets advance
the stored state.

## Consequences

Refrigerator-sized changes are covered immediately, while short large loads still reach 800 W in
bounded steps. When the battery is full, output may exceed measured plug consumption; unmeasured
household loads consume that power first and the remainder may be exported. The controller can
observe battery response but cannot calculate actual grid export without a whole-house meter.
