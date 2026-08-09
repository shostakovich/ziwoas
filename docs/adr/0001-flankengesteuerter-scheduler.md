# Der Schaltzeit-Scheduler ist flankengesteuert, nicht zustandsabgleichend

Der Zeitplan schaltet **nur im Moment einer fälligen Flanke** und gleicht danach nie einen
Soll-Zustand ab: wer nach einer Schaltung von Hand eingreift, behält den Zustand bis zur
nächsten Flanke. Genau das macht die zentrale Zusage möglich — eine Steckdose, für die es
nur Aus-Schaltzeiten gibt, bleibt aus, bis ein Mensch sie wieder einschaltet.

Die Alternative wäre ein Soll-Ist-Abgleich („zwischen 10:00 und 20:00 soll die Steckdose an
sein"), der ein manuelles Ausschalten innerhalb eines Zeitfensters binnen einer Minute
zurücknehmen würde. Für ein Haus, in dem der Mensch anwesend ist, ist das die falsche
Rangordnung: die letzte menschliche Handlung gewinnt.

## Consequences

- Ein Zeitfenster ist **kein Zustand**, sondern zwei unabhängige Flanken. Es existiert nur
  in der Darstellung; die Kantenberechnung kennt es nicht.
- Verpasste Flanken (Server aus, Broker weg) werden nur innerhalb einer kurzen **Karenz**
  nachgeholt. Verspätetes Schalten ist gefährlicher als gar nicht zu schalten — ein
  Verbraucher kann in Benutzung sein.
- Der Zeitplan kann den tatsächlichen Gerätezustand nicht garantieren. Wer Verlass auf
  „ist jetzt aus" braucht, muss `PlugState` lesen, nicht den Zeitplan.
