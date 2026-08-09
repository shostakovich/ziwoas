# ZiWoAS

Haus-Automatisierung für eine Wohnung: Strommessung und -steuerung (Solakon-Wechselrichter,
Shelly-Steckdosen), Lampen, Sensoren und Wetter — ein einziger Kontext.

## Language

### Schalten

**Steckdose**:
Eine Shelly-Steckdose, die einen Verbraucher schaltet und misst. Lebt nicht in der Datenbank,
sondern als Eintrag in `config/ziwoas.yml`; DB-Zeilen verweisen nur über ihre String-`id`
darauf.
_Avoid_: Plug (im deutschen UI-Text), Gerät

**Schaltbar**:
Eigenschaft einer Steckdose, die sie überhaupt erst für Zeitplan und Schaltknopf sichtbar
macht. Nicht schaltbare Steckdosen werden nur gemessen.

**Schaltzeit**:
Eine wiederkehrende Regel für **eine** Steckdose: an einem Wochentagssatz zu einer Uhrzeit
entweder ein- oder ausschalten. Die kleinste Einheit des Zeitplans.
_Avoid_: Schaltpunkt, Termin, Zeitfenster (das ist das Paar)

**Zeitfenster**:
Ein zusammengehörendes Paar aus einer Ein- und einer Aus-Schaltzeit („an von 10:00 bis
20:00"). Reine Darstellungs- und Bedienklammer — für die Kantenberechnung existiert es nicht.
_Avoid_: Fenster, Intervall, Zeitraum

**Einzelschaltung**:
Eine Schaltzeit ohne Partner („täglich 22:00 aus"). Sie schaltet und überlässt die
Gegenrichtung dem Menschen.

**Flanke**:
Der konkrete Zeitpunkt, an dem eine Schaltzeit fällig wird — Regel plus Datum. Was der
Scheduler tatsächlich abarbeitet.
_Avoid_: Edge (im deutschen UI-Text), Event, Trigger

**Karenz**:
Die Frist, innerhalb derer eine verpasste Flanke noch nachgeholt wird. Danach verfällt sie
ersatzlos, statt verspätet zu schalten.
_Avoid_: Grace Period (im deutschen UI-Text; im Code heißt die Konstante `GRACE`), Nachlauf, Toleranz

**Manuelle Schaltung**:
Ein Schaltbefehl, der vom Menschen kommt — über den Knopf in der App oder am Gerät selbst.
Gegenstück zur Schaltung aus dem Zeitplan.

**Verwaist**:
Zustand einer Schaltzeit, deren Steckdose in `config/ziwoas.yml` nicht mehr schaltbar ist
oder ganz fehlt. Sie schaltet nichts, bleibt aber erhalten und lebt wieder auf, sobald die
Steckdose zurückkommt.
