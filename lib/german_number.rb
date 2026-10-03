# Numbers the way German readers write them: a decimal comma, a dot between
# thousands, and a true minus sign (U+2212) rather than the hyphen, so a
# negative value is as wide as a positive one in tabular figures and lines up
# with a plus sign.
module GermanNumber
  MINUS = "−".freeze

  # extend self, not module_function: see Shading.
  extend self

  def format(value, precision: 0)
    rounded = value.to_f.round(precision)
    integer, fraction = Kernel.format("%.#{precision}f", rounded.abs).split(".")
    grouped = integer.reverse.scan(/\d{1,3}/).join(".").reverse

    "#{MINUS if rounded.negative?}#{[ grouped, fraction ].compact.join(',')}"
  end
end
