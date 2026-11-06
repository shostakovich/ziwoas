# A Govee lamp's LAN reply wins over the cloud

ZiWoAS hears a Govee lamp two ways: the lamp's own status replies on the LAN, and the Govee
cloud. Since the reconciler ported from the Rails app (no ADR recorded it), a LAN reading that
disagreed with the shown state asked the cloud, and the cloud's answer was shown. A
disagreement that never resolved, such as LAN and cloud describing a colour differently, asked
the cloud on every LAN reading (every 8 s, every 2 s while a lamp is being powered up) and could
use up the daily quota. An answer requested before a command still flipped the tile back, and a
cloud reporting a lamp offline showed it off and unreachable while it was answering on the LAN
(#210).

What a lamp reports about itself on the LAN is now what ZiWoAS shows. The cloud only fills in
what the LAN cannot see.

- **A lamp heard on the LAN** has sent a status reply and is not silent as ADR-0010 defines it;
  a scan reply alone carries no state and does not count. It shows its LAN reply as it comes:
  on/off, brightness, colour, colour temperature. Within the pending window after a command a
  reading that disagrees is still taken for the lamp not having applied it yet, and the cloud's
  zone states are ignored, since the cloud lags behind a zone command.
- **The cloud poll** skips a plain lamp heard on the LAN and gives a zone lamp heard on the LAN
  its zone states, nothing else. Any other lamp takes its full state from the poll,
  reachability included: ADR-0010's "reachable means heard on the LAN" only decides when a lamp
  being powered up has answered, while the stored reachability of a lamp not heard on the LAN
  comes from the cloud.
- **Between polls the cloud is asked only for zone lamps**, and only when their LAN reply differs
  from the one before, the first reply after a start included. One such request per lamp is in
  flight at a time; a change while it runs asks nothing more.
- **Outdated answers are discarded.** Every cloud answer, from the poll or from such a request,
  is dropped if the lamp was commanded after the request went out. A LAN command counts when it
  is sent, a cloud-routed command once its control call succeeds.

## Consequences

- A lamp whose LAN reply never changes asks the cloud nothing between polls, however much the
  cloud disagrees, and a plain lamp heard on the LAN not even in the poll; the quota no longer
  depends on how often the LAN is read.
- How LAN and cloud each map colour against colour temperature no longer matters for a lamp
  heard on the LAN.
- A zone switched in the Govee app while the lamp's LAN reply stays the same shows up with the
  next poll only.
