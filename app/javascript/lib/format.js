// Numbers the way German readers write them, matching GermanNumber in Ruby:
// a decimal comma, a dot between thousands, a true minus (U+2212) and a space
// before the unit or the percent sign.
//
//   import { formatNumber, formatWatts, formatPercent, formatFlow } from "lib/format"
//
//   formatNumber(1234.5)                       // "1.235"
//   formatNumber(-0.25, { decimals: 2 })       // "−0,25"
//   formatNumber(0.8, { unit: "kWh", decimals: 1 }) // "0,8 kWh"
//   formatWatts(1980.4)                        // "1.980 W"
//   formatPercent(76)                          // "76 %"
//   formatFlow(-180, { positive: "lädt", negative: "entlädt" }) // "entlädt 180 W"
//
// A missing value (null, undefined, NaN) reads "—", with its unit if any.

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

// A signed power flow in words instead of a sign: "lädt 180 W", "entlädt 180 W".
// What rounds to zero is no flow: "0 W".
export function formatFlow(value, { positive, negative, unit = "W", decimals = 0 }) {
  if (missing(value)) return withUnit(DASH, unit)
  const magnitude = formatNumber(Math.abs(Number(value)), { decimals, unit })
  if (!/[1-9]/.test(magnitude)) return magnitude
  return `${Number(value) > 0 ? positive : negative} ${magnitude}`
}
