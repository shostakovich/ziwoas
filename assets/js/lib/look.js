import { themeColor, onThemeChange } from "./theme_colors.js"

const COOKIE_MAX_AGE_S = 20 * 365 * 24 * 60 * 60

export function currentLook() {
  return document.documentElement.dataset.look === "felt" ? "felt" : "clean"
}

function setLook(look) {
  const root = document.documentElement
  if (look === "felt") root.dataset.look = "felt"
  else delete root.dataset.look

  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  document.cookie = `look=${look === "felt" ? "felt" : "clean"}; Max-Age=${COOKIE_MAX_AGE_S}; Path=/; SameSite=Lax${secure}`
}

function paintThemeColor() {
  const meta = document.querySelector("meta[name='theme-color']")
  if (meta) meta.content = themeColor("--felt-body-bg")
}

window.addEventListener("ziwoas:set-look", (event) => setLook(event.detail.look))
onThemeChange(paintThemeColor)
paintThemeColor()
