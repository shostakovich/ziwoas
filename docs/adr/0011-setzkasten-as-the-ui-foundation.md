# Setzkasten is the UI foundation; ZiWoAS keeps its palette and its widgets

**Status:** Accepted. Supersedes [ADR-0005](0005-felt-css-as-the-ui-foundation.md).
Amended 2026-10-31 (#196): honey selection, own chart series, six-entry dock, phone density.

felt-css gave ZiWoAS Bootstrap's class names, dark mode and a felt look, but no components: every
page assembled cards, forms, flashes and navigation from classes, and the app kept its own
`core_components` in felt's markup. Setzkasten, a Phoenix component library by the same author,
brings what felt-css lacks: HEEx components (shell, header, card, stat, input, button, flash,
confirmation dialog, theme toggle) with their accessibility settled, on Tailwind 4 and daisyUI 5,
and a design system that says where each belongs. ZiWoAS moves to it (#185). Where Setzkasten's
conventions and felt-css habits disagree, Setzkasten wins.

- **Palette.** ZiWoAS keeps its stronger hues (cobalt, honey, moss, tomato, petrol) for the
  whole UI, light and dark, as an override of Setzkasten's themes in `assets/css/palette.css`.
  Surfaces, type and radii come from Setzkasten; the selection is honey, a palette override of
  `--color-selected`.
- **No felt look.** The look toggle, its cookie and the felt texture go. A theme toggle (System,
  Hell, Dunkel) takes its place, System by default, kept per device.
- **Shell.** Setzkasten's top bar, `:default` wide on every page. On phones the dock holds all
  six pages, the current one as a pill in the selection colour.
- **Widths.** Pages are `:default`; forms and settings (Wirtschaftlichkeit, a lamp) `:narrow`.
- **Flat pages.** Lists, forms and pickers sit on the page; cards only for tiles, charts, lamps
  and plugs. Section headings in sentence case; deletes ask in Setzkasten's confirmation dialog.
- **Live data.** Home and PV check freshness on the server (`ZiwoasWeb.LiveFreshness`): after
  the plugs' offline time without a plug delta or inverter reading, the header says "veraltet"
  and since when, and live stats are `stale`. Nothing fades.
- **Icons.** The plush icons stay (`ZiwoasWeb.Plush`); UI glyphs such as back, chevrons,
  play/pause, edit and delete are Lucide icons (`ZiwoasWeb.Icons`, vendored from lucide-static).
- **Data colours.** ZiWoAS sets its own, more vivid chart series in `palette.css`; the tokens in
  `assets/css/application.css` map roles onto them:
  solar on series 2, grid and consumption on series 1, battery on series 3, warning and danger
  lines on 2 and 4. Categorical series take the series their chart leaves free: consumer plugs
  by their energy in the 30 days up to the newest aggregated day
  (`Ziwoas.Plugs.consumer_rank/2`, ties and plugs without data in config order), the same on
  every page and for every range, so a plug keeps its colour; sensors in config order (`ZiwoasWeb.Charts.Series` and `Charts.Categories` on the
  server, `chart_theme.js` and `consumer_series.js` in the hooks, which get the rank as
  `consumer_order`); on charts, more categories than free series are grouped as "Weitere" in
  `chart-other`, `color: :other` in a legend, while Home's share bar names each of them in
  `chart-other`. The total consumption line (`--color-chart-total`) is the consumption colour,
  series 1 with a line marker in a legend. Of the neutral marks, the zero line mixes base-content into base-100; gridlines, bands,
  gaps and stand-in marks lay base-content over transparent, the halo base-100.
  `assets/js/lib/chart_theme.js` paints every chart from them.
- **App widgets stay in the app**: energy flow, CO₂ gauge, sun calendar, yield map, plush knobs,
  colour swatches, the colour-temperature slider and the weather strips, restyled on Tailwind and
  daisyUI tokens.
- **Gaps go upstream.** What Setzkasten lacks or gets wrong is fixed in Setzkasten, not worked
  around here, as the graphic chart colours and the six-entry dock were. Phone density is
  ZiWoAS's own choice, not a gap: `assets/css/phone.css` tightens Setzkasten's cards, tiles,
  headings and dock below `md`.

The alternative, staying on felt-css, was rejected: each page would keep re-assembling components
from classes, and ZiWoAS would remain the only app on a stylesheet the others do not share.

## Consequences

- Tailwind and esbuild build the assets; daisyUI (only its bundle) and Setzkasten are git
  dependencies from GitHub, and Tailwind imports Setzkasten's CSS through `NODE_PATH`.
  `assets.deploy` compiles first, since `app.js` imports the hooks Setzkasten's compilation
  writes.
- No stylesheet comes from another host any more; Figtree is served from Setzkasten's
  `priv/static` and preloaded.
- Own CSS in `assets/css/` covers the app widgets and `phone.css`, on Tailwind and daisyUI
  tokens: no hex, no `light-dark()`, Tailwind's breakpoints.
