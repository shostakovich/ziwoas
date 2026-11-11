# Schalten shows one view at a time, chosen per resident

ADR-0014 grouped Schalten by room and put every room on one long page; a bar of room chips
jumped to a room without hiding the others. A resident who mostly switches the same few lamps,
or lives mostly in one room, still scrolled past everything else each time. With the resident
known from the gate (ADR-0016), Schalten can show less and remember what each resident wants
(#217).

- **One view at a time.** The chips pick what the page shows: „Alle“ (every room, as before),
  „Favoriten“, one room, or „Ohne Raum“. The view is part of the address (`?raum=`, next to
  the kind filter `?nur=`), so reloading, sharing a link or going back from a device's page
  (`?von=`) lands on the same view. The scroll-tracking chip bar is gone.
- **The summaries still describe the whole home.** Choosing a kind shows it across all rooms,
  whatever view was chosen; „Alle zeigen“ leads back to the resident's default view.
- **„Lampen aus“ stays per room.** Under „Alle“ there is also „Alle Lampen aus“. The favourites
  have none: they span rooms, and a button there would switch off lamps the resident did not
  star.
- **Favourites are their own view.** A resident stars a lamp, a heater or a switchable plug on
  the device's page. The star is not on the tile, where it would compete with the knob. A
  favourite also stays in its room; „Favoriten“ lists them in the order of „Alle“, by room
  order and then by kind, and its chip appears only once there is one.
- **Each resident sets a default view.** „Als Standard“ on „Alle“, „Favoriten“ or a room makes
  Schalten open there when the address names no view. „Ohne Raum“ is a place to tidy up, not a
  place to start, so it offers none.
- **A view that cannot be shown shows „Alle“.** An unknown room, a room without devices, an
  empty „Favoriten“ or a default whose room was deleted all fall back to „Alle“; a deleted room
  takes its default row with it.
- **Without a resident the view is shared.** Reached without the gate, Schalten opens with
  „Alle“ and offers neither star nor „Als Standard“; everything still switches.

## Consequences

- Favourites and default views live in the database (`favourites`, `default_views`), keyed by
  the resident's login name, as ADR-0016 describes. A favourite whose device is gone stays
  stored and is not shown; it counts again if the device comes back.
- The order of rooms stays shared: it comes from the Räume page for everyone.
