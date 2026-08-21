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
  off now" must read `PlugState`, not the schedule.
