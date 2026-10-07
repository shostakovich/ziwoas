# felt-css is the UI foundation; our own CSS covers only ZiWoAS widgets

The app's look used to live in one hand-written `application.css` of some 1,600 lines with its
own colour variables, breakpoints and component classes. It now builds on felt-css, a pure-CSS
library with Bootstrap 5.3 class names, loaded from `https://felt-css.rocu.de/felt.css` before
our stylesheets. Markup uses its components and utilities (`card`, `stat`, `nav-pills`,
`form-switch`, `<dialog class="modal">`, spacing and text utilities); nothing of Bootstrap's
JavaScript is loaded.

- **Looks.** Clean is the default. A toggle in the header switches to Felt (wool felt with seams);
  the choice is stored in a permanent `look` cookie and the layout sets `data-look="felt"` on
  `<html>` server-side, so pages render in the chosen look without a flash. Switching looks never
  changes layout.
- **Dark mode** follows the system. felt-css tokens are `light-dark()` values, so anything styled
  with tokens (`--felt-surface`, `--felt-body-color`, `--felt-secondary-color`,
  `--felt-warning`, …) adapts on its own.
- **Data colours** are the `--viz-*` tokens in `application.css` (solar, battery, grid, muted and
  ten categorical colours, assigned by entity, never cycled), derived from the felt palette. They
  are the only place colour values are defined. Canvas charts cannot read tokens directly:
  `lib/theme_colors.js` resolves them to sRGB and reports theme changes, and `lib/chart_theme.js`
  is the one Chart.js plugin every chart uses — datasets name a `tone` token, the plugin paints
  series, axes, legend and tooltip and repaints when the scheme or look changes.
- **Own CSS** (`app/assets/stylesheets/*.css`, one file per area) exists only for widgets felt-css
  has no answer for: plush knobs and icons, the energy-flow and sun SVG charts, weather segments,
  colour swatches. It uses tokens only, no hex values, and felt's breakpoints (576/768/992 px).

The alternative, keeping and modernising the hand-written stylesheet, was rejected: felt-css was
built with ZiWoAS in mind, gives dark mode and a second look for free, and turns most styling
into markup a reader already knows from Bootstrap.

## Consequences

- The UI needs `felt-css.rocu.de` reachable (stylesheet and its texture images); without it pages
  fall back to unstyled markup plus our widget CSS.
- Gaps that are generic rather than ZiWoAS-specific belong in felt-css, not in our stylesheets.
- felt's utilities are `!important` inside a cascade layer and cannot be overridden from our
  unlayered CSS; change the class in the markup instead. On felt components (`.card`, `.btn`,
  `.navbar`, …) avoid `background`/`border`/`box-shadow` shorthands, which erase the felt texture.

_Note (Phoenix, ADR-0007):_ the stylesheets live in `assets/css/` (`application.css` with the
`--viz-*` tokens, one file per area), the chart helpers in `assets/js/lib/theme_colors.js` and
`assets/js/lib/chart_theme.js`; esbuild bundles them. The look cookie is set by `PATCH /look`
and carried into LiveViews by `ZiwoasWeb.Look`.
