# An amount of energy. Watt-hours are canonical: everything is summed, subtracted and
# compared in Wh, and kilowatt-hours are a display conversion the caller rounds itself.
class Energy < Dry::Struct
  module Types
    include Dry.Types()
  end

  attribute :wh, Types::Coercible::Float

  ZERO = new(wh: 0.0)

  class << self
    def wh(value) = new(wh: value)

    def kwh(value) = new(wh: value * 1000.0)

    def zero = ZERO

    def sum(energies) = wh(energies.sum(&:wh))
  end

  def kwh = wh / 1000.0

  def +(other) = Energy.wh(wh + other.wh)

  def -(other) = Energy.wh(wh - other.wh)

  def /(divisor) = Energy.wh(wh / divisor)

  def zero? = wh.zero?

  def negative? = wh.negative?

  def ratio_to(other) = other.zero? ? 0.0 : wh / other.wh
end
