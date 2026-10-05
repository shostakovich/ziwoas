module Look
  Name = Dry::Types["string"].enum("clean", "felt")

  DEFAULT = "clean"
  COOKIE = :look

  # The browser chrome follows the page background (felt-css --body-bg).
  THEME_COLORS = {
    "clean" => { light: "#f6f7f9", dark: "#212529" },
    "felt" => { light: "#dbcdb7", dark: "#242220" }
  }.freeze

  def self.named(value) = Name.valid?(value) ? value : DEFAULT

  def self.theme_colors(look) = THEME_COLORS.fetch(look)
end
