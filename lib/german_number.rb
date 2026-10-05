# A true minus (U+2212) is as wide as a plus in tabular figures.
# The twin of formatNumber and formatFlow in app/javascript/lib/format.js.
module GermanNumber
  MINUS = "−".freeze
  MISSING = "—".freeze

  # extend self, not module_function: see Shading.
  extend self

  def format(value, precision: 0, unit: nil)
    with_unit(digits(value, precision), unit)
  end

  def flow(value, positive:, negative:, unit: "W", precision: 0)
    magnitude = digits(value&.abs, precision)
    return with_unit(magnitude, unit) unless magnitude.match?(/[1-9]/)

    "#{value.positive? ? positive : negative} #{with_unit(magnitude, unit)}"
  end

  private

  def digits(value, precision)
    number = value&.to_f
    return MISSING if number.nil? || number.nan?

    rounded = number.round(precision)
    integer, fraction = Kernel.format("%.#{precision}f", rounded.abs).split(".")
    grouped = integer.gsub(/\B(?=(\d{3})+\z)/, ".")

    # -0.0 is not negative: a value that rounds to zero carries no sign.
    "#{MINUS if rounded.negative?}#{[ grouped, fraction ].compact.join(',')}"
  end

  def with_unit(text, unit) = unit ? "#{text} #{unit}" : text
end
