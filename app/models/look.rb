# How felt-css draws the pages: Clean by default, wool felt on request. The
# choice lives in a cookie, so anything that is not a known look reads as Clean.
module Look
  Name = Dry::Types["string"].enum("clean", "felt")

  DEFAULT = "clean"
  COOKIE = :look

  # The browser chrome follows the page background (felt-css --body-bg).
  THEME_COLORS = {
    "clean" => { light: "#f6f7f9", dark: "#212529" },
    "felt" => { light: "#e7dccb", dark: "#242220" }
  }.freeze

  def self.named(value) = Name.valid?(value) ? value : DEFAULT

  def self.theme_colors(look) = THEME_COLORS.fetch(look)
end
