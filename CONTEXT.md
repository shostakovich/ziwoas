# ZiWoAS

Home automation for an apartment: power measurement and control (Solakon inverter,
Shelly plugs), lights, sensors, and weather — a single context.

## Language

### Switching

**Plug**:
A Shelly plug that switches and measures a consumer. It doesn't live in the database, but
as an entry in `config/ziwoas.yml`; DB rows reference it only via their string `id`.
_German UI_: Steckdose
_Avoid_: Plug (in German UI text), Device

**Switchable**:
Property of a plug that makes it visible to the schedule and the switch button in the
first place. Non-switchable plugs are only measured.
_German UI_: Schaltbar

**Switch time**:
A recurring rule for **one** plug: switch on or off at a time of day on a set of
weekdays. The smallest unit of the schedule.
_German UI_: Schaltzeit
_Avoid_: Schaltpunkt, Termin, Time window (that's the pair)

**Time window**:
A matched pair of an on and an off switch time ("on from 10:00 to 20:00"). A pure
presentation and interaction grouping — it doesn't exist for the edge calculation.
_German UI_: Zeitfenster
_Avoid_: Fenster, Intervall, Zeitraum

**Single switch**:
A switch time without a partner ("off daily at 22:00"). It switches and leaves the
opposite direction to the human.
_German UI_: Einzelschaltung

**Edge**:
The concrete point in time at which a switch time falls due — rule plus date. What the
scheduler actually works through.
_German UI_: Flanke
_Avoid_: Edge (in German UI text), Event, Trigger

**Grace**:
The deadline within which a missed edge is still made up. After that it lapses for good,
instead of switching late.
_German UI_: Karenz
_Avoid_: Grace Period (in German UI text; the code constant is `GRACE`), Nachlauf, Toleranz

**Manual switch**:
A switch command that comes from the human — via the button in the app or on the device
itself. Counterpart to the switch coming from the schedule.
_German UI_: Manuelle Schaltung

**Orphaned**:
State of a switch time whose plug is no longer switchable in `config/ziwoas.yml`, or is
missing entirely. It switches nothing but stays around and comes back to life as soon as
the plug returns.
_German UI_: Verwaist

### Measuring

**Measurement**:
A single report from a plug: power in watts at a point in time. Shelly plugs report on
change, Fritz plugs are polled — so the intervals aren't even.
_German UI_: Messwert
_Avoid_: Sample (in German UI text), Messung

**Offline**:
A plug from which no measurement has arrived for a while — unplugged, Wi-Fi gone, broker
dead. The deadline is fixed in `Plugs::Measurement::OFFLINE_AFTER_S` and applies equally to
all plugs: what's offline is neither shown nor counted. Zero watts isn't offline — a plug
with nothing running on it keeps on reporting.
_German UI_: Offline
_Avoid_: Stale (that's the inverter's deadline), Stumm, Abgezogen

**Stale**:
A reading from the inverter that's too old to describe its current state. Its own
deadline in `SolakonReading::STALE_AFTER_S` — a plug and an inverter report at different
intervals for different reasons, which is why there are two deadlines and not one. If the
reading is stale, the inverter counts as offline and every value derived from it is
unknown, not zero.
_German UI_: Veraltet
_Avoid_: Offline (that's the state of a plug), Stale (in German UI text)

**Plug roster**:
The configured plugs together with their roles. The one place that knows who produces and
who consumes, and which sign a measurement carries — every reader asks the roster instead
of comparing roles itself. `Plugs::Roster`, reachable as `config.plug_roster`.
_German UI_: Steckdosenverzeichnis
_Avoid_: Plug list, Registry, Verzeichnis (in German UI text)

**Power series**:
The average power of a set of plugs over a run of equal time buckets. Producers report
`apower_w` with the opposite sign; the roster applies that convention once, so every reader
downstream sees production as a positive magnitude.
_German UI_: Messreihe
_Avoid_: Bucket list, Time series, Samples

**Live state**:
The household as it is right now, as one answer: every plug resolved against the **offline**
deadline, the inverter's newest reading against the **stale** deadline, and the energy flow that
follows from both. `LiveState`, the only thing `/api/live` renders. It owns neither deadline — it
is the one place they are applied together, which is why a plug the flow dropped is offline in the
same payload.
_German UI_: Live-Bild
_Avoid_: Live data, Snapshot, Live payload, Realtime state
