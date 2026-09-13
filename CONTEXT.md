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

**Energy**:
An amount of energy as one value. Watt-hours are canonical — everything is summed,
subtracted and compared in Wh; kilowatt-hours are a display conversion, and rounding
happens only where a number is rendered. `Energy`, `lib/energy.rb`.
_German UI_: Energie
_Avoid_: kWh value, Wh float

**Offline**:
A plug from which no measurement has arrived for a while — unplugged, Wi-Fi gone, broker
dead. The deadline is fixed in `Plugs::Measurement::OFFLINE_AFTER_S` and applies equally to
all plugs: what's offline is neither shown nor counted. Zero watts isn't offline — a plug
with nothing running on it keeps on reporting.
_German UI_: Offline
_Avoid_: Stale (that's the inverter's deadline), Stumm, Abgezogen

**Stale**:
A reading from the inverter that's too old to describe its current state. Its own
deadline in `Solakon::Reading::STALE_AFTER_S` — a plug and an inverter report at different
intervals for different reasons, which is why there are two deadlines and not one. If the
reading is stale, the inverter counts as offline and every value derived from it is
unknown, not zero.
_German UI_: Veraltet
_Avoid_: Offline (that's the state of a plug), Stale (in German UI text)

**Panel**:
One of the inverter's four PV inputs, each carrying a single module. All four are read and
stored on every reading — a panel without yield reports 0 W, it does not go absent. Total PV
power is their sum, never a figure stored in its own right. `Solakon::Snapshot#panels`.
_German UI_: Panel
_Avoid_: String, Strang, MPPT-Eingang. `PV_STRINGS` in `lib/solakon/client.rb` names the
Modbus layer, not the domain, and stays.

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

### Control

**Control**:
Setting the inverter's output so it follows the household instead of a fixed schedule. It
works from what the plugs measure and from the battery's reaction — there is no
whole-house meter, so the grid flow itself is never seen. Control is therefore named after
what it follows, not after an export figure it cannot measure (ADR-0002).
_German UI_: Regelung, Auto-Regelung
_Avoid_: Nulleinspeisung, Zero export (both promise a measured quantity that does not
exist here), Steuerung (that is the one-way write, not the loop)

**Control tick**:
One pass of the loop: read the household, decide a target, write it to the inverter.
Everything the loop remembers between ticks is the target it actually wrote — an attempt
that never reached the inverter is not remembered. Each successful write also re-arms the
inverter's own remote-control watchdog, which is why a target is written every tick and
not only when it changes.
_German UI_: Regeltakt
_Avoid_: Zyklus, Durchlauf, Heartbeat

**Guaranteed floor**:
The lowest total consumption the measured consumers reached over the last 24 hours. Stands
in for the live sum whenever no fresh **measurement** is available: it is the amount that
can be covered without guessing.
_German UI_: Gesicherte Grundlast
_Avoid_: Grundlast alone (that is the general term), Baseline, Minimum

**Surplus control**:
The mode entered once the battery is full and still charging: the target no longer follows
consumption but the battery's reaction, rising while it charges and falling while it
discharges. The load-following target stays the lower bound, so measured consumption keeps
first claim. Power beyond that goes to unmeasured loads first and may leave the house.
_German UI_: Überschussregelung
_Avoid_: Einspeisung, Export mode, Overshoot

**Probe**:
A single small increase of the target, offered once when the battery is full and reported
PV has already been curtailed to near zero. If the battery keeps discharging, the probe is
rejected and not repeated until charging proves that surplus is back. The only way to ask
a question of a system that has stopped reporting the answer.
_German UI_: Tastversuch
_Avoid_: Test, Versuch alone, Ping

**Deadband**:
The band around zero within which the battery's measured power does not move the target.
Keeps noise from being read as a signal.
_German UI_: Totband
_Avoid_: Toleranz (that is the switching **grace**), Hysterese, Schwelle

### Sun

**PV power**:
The DC power the inverter reads from its panels at a point in time: the sum of the four
**panels**, before battery and conversion. What the sun delivers to the array, not what the
house receives. Exists only since the inverter reports; the **energy** the producer plug
measures is a different quantity (AC, and since the battery also its discharge).
_German UI_: PV-Leistung
_Avoid_: Ertrag, Erzeugung (both are the plug's quantity), Production, Solar

**PV energy**:
**PV power** integrated over a period, in Wh — per hour or per day. The daily sum on the sun
calendar is this, not the plug's **energy**.
_German UI_: PV-Energie, "PV-Energie je Tag"
_Avoid_: Tagesertrag, Ertrag (the plug's energy), Yield

**Irradiance**:
Global radiation the weather station measured over an hour, per square metre. Comes from the
historic weather record, as average power (W/m²). The reference for what the sun offered,
independent of the array.
_German UI_: Einstrahlung
_Avoid_: Sonnenschein (that is minutes of sunshine), UV, Solar, Strahlung alone

**Sun position**:
Where the sun stands for the configured location at a point in time: azimuth and elevation.
Computed, never measured.
_German UI_: Sonnenstand
_Avoid_: Sonnenbahn (that is the whole day's curve), Sonnenhöhe alone

**Sun path**:
The sun positions over one day, drawn as a curve. Sunrise and sunset are its ends.
_German UI_: Sonnenbahn
_Avoid_: Tagbogen, Sonnenverlauf

**Yield ratio**:
**PV power** divided by **irradiance** for one hour, relative to the best hour ever observed.
Reads as "how much of what the sun offered arrived at the array". Below the best hour means
something stood in the way: **shading**, **curtailment**, or orientation.
_German UI_: Ausbeute
_Avoid_: Ertragsquote (Ertrag is the plug's quantity), Wirkungsgrad, Performance Ratio, Quote alone

**Shading**:
A **sun position** at which the **yield ratio** stays low again and again, because something
between sun and panel casts a shadow. A property of the garden, read off the map of sun
positions, never of a single hour.
_German UI_: Abschattung
_Avoid_: Schatten alone, Verschattung, Shadow

**Curtailment**:
The inverter holding **PV power** below what the sun offers because the battery is full and
nothing takes the surplus (ADR-0002). Looks like **shading** for an hour and is none. Counted
in the yield ratio on purpose: it is a state of the house, and one that is meant to disappear
once surplus is fed to the grid.
_German UI_: Drosselung
_Avoid_: Abregelung, Abschattung, Curtailment (in German UI text)
