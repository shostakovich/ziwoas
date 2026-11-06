# Schalten groups by room, and rooms live in the database

The Schalten tab had grown to many lamps, heaters and plugs in three long lists by kind, each
card carrying its own schedule. The residents could no longer find a device or see at a glance
what was still on. Schalten now groups every device by the room it stands in, as Apple Home,
Google Home and Home Assistant do, and a device's schedule moves to its own page.

Rooms live in the database, not in `ziwoas.yml`: they are something the residents set up and
change in the app, like the cost items of ADR-0004. Editing a file on the server to move a lamp
to another room is not something either resident should have to do.

- **A room is a name and a place in the order.** `Ziwoas.Rooms` owns them; `/switches/rooms`
  adds, renames, reorders and deletes them.
- **Every device stands in at most one room.** Lamps and heaters, already rows of their own,
  carry a `room_id`. Plugs are still defined in `ziwoas.yml`, so their room is a `plug_rooms`
  row keyed by plug id. A device without a room, new ones included, stands under „Ohne Raum“
  at the end. Deleting a room leaves its devices without one.
- **A plug that powers a lamp stays a tile of its own.** Behind it there is often a power strip
  with more than the lamp; its page names the lamps that hang on it.
- **The tile switches, its name opens the page.** Schaltzeiten and Zeitfenster are edited on
  `/switches/plugs/:id` and `/switches/heaters/:key`; the tile shows only the next switch time.
  The Heiztemperatur keeps its ± on the tile, since it takes effect at once like a switch.
- **„Lampen aus“ switches lamps only.** A room's button and the lamp filter's „Alle Lampen aus“
  never switch a plug off: a plug off behind someone's back is worse than a lamp left on.
- **The page opens with what is on.** Summaries per kind (lamps on, heaters heating, plugs on
  with their watts) filter the page to that kind across rooms (`?nur=lampen`); a sticky bar of
  room chips jumps to a room without hiding the others.

## Consequences

- A plug's `room` key in `ziwoas.yml` was never read and still is not; a plug gets its room on
  its page.
- Sensors still take their room from `ziwoas.yml`. A room's air shows in its heading when a
  sensor's `room` is spelled like the room; moving sensors into the database is the next step.
- Lamps and heaters appear under „Ohne Raum“ until someone places them, so a new install shows
  everything there at first.
