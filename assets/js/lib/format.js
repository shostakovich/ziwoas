// The twin of ZiwoasWeb.Format: decimal comma, dot between thousands, true minus (U+2212).

const MINUS = "−"
const DASH = "—"
const formatters = new Map()

function formatter(decimals) {
  if (!formatters.has(decimals)) {
    formatters.set(decimals, new Intl.NumberFormat("de-DE", {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
      useGrouping: "always",
    }))
  }
  return formatters.get(decimals)
}

function missing(value) {
  return value == null || Number.isNaN(Number(value))
}

function withUnit(text, unit) {
  return unit ? `${text} ${unit}` : text
}

export function formatNumber(value, { decimals = 0, unit } = {}) {
  if (missing(value)) return withUnit(DASH, unit)
  const text = formatter(decimals).format(Math.abs(Number(value)))
  // A value that rounds to zero carries no sign.
  const negative = Number(value) < 0 && /[1-9]/.test(text)
  return withUnit(negative ? `${MINUS}${text}` : text, unit)
}

export function formatWatts(value, { decimals = 0 } = {}) {
  return formatNumber(value, { decimals, unit: "W" })
}

// value in percent (76 for 76 %), not as a fraction.
export function formatPercent(value, { decimals = 0 } = {}) {
  return formatNumber(value, { decimals, unit: "%" })
}

export function formatFlow(value, { positive, negative, unit = "W", decimals = 0 }) {
  if (missing(value)) return withUnit(DASH, unit)
  const magnitude = formatNumber(Math.abs(Number(value)), { decimals, unit })
  if (!/[1-9]/.test(magnitude)) return magnitude
  return `${Number(value) > 0 ? positive : negative} ${magnitude}`
}
