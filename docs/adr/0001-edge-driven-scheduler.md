# The switch-time scheduler is edge-driven, not state-reconciling

The schedule switches **only at the moment of a due edge** and never afterwards reconciles
against a target state: whoever intervenes by hand after a switch keeps that state until
the next edge. That's exactly what makes the central promise possible — a plug that only
has off switch times stays off until a human turns it back on.

The alternative would be a target/actual reconciliation ("between 10:00 and 20:00 the plug
should be on"), which would undo a manual switch-off within a time window within a minute.
For a home where the human is present, that's the wrong order of precedence: the last
human action wins.

## Consequences

- A time window is **not a state**, but two independent edges. It exists only in the
  presentation; the edge calculation doesn't know it.
- Missed edges (server down, broker gone) are only made up within a short **grace**
  period. Switching late is more dangerous than not switching at all — a consumer may be
  in use.
- The schedule cannot guarantee the actual device state. Whoever needs to rely on "it's
  off now" must read `Plugs::State`, not the schedule.

_Note (Phoenix, ADR-0007):_ the plug state is `Ziwoas.Plugs.State` today, the scheduler
`Ziwoas.Switching.ScheduleTickJob` with its grace in `grace_s/0`.

## Addendum: heaters (#205)

Heaters follow the same edges, latest edge wins (ADR-0013), with two differences.

- **No grace.** After downtime the latest due edge applies at once, however late. Switching a
  heater late is harmless; heating all night because an edge was missed is not.
- **Manual heating is capped at four hours.** Four hours after a press to heat, the heater
  switches to frost protection, unless a window is active then. Every evening at 22:00 it
  does the same, with the same exception.
- **Overlapping windows are one.** A window's end switches to frost protection only if no
  other window is active then.

### Consequences

- The minute tick decides the state from all edges up to now, not from the edges since its
  last run, and writes only when the state changes; it keeps no watermark.
