module Shading
  class DailyProfiles
    KEYS = %i[measured expected theory].freeze

    def initialize(best_ratio:)
      @best_ratio = best_ratio
    end

    def build(hours)
      hours.group_by { |hour| hour.time.month }.sort.map do |month, group|
        basis = comparable(group)
        Profile.new(month: month, days: basis.map(&:date).uniq.length, curves: Shading.trim(curves(basis)))
      end
    end

    private

    def comparable(hours)
      measured = hours.reject { |hour| hour.irradiance_w_per_m2.nil? }
      measured.empty? ? hours : measured
    end

    def curves(hours)
      by_hour = hours.group_by { |hour| hour.time.hour }.sort

      [
        curve(:measured, by_hour, &:pv_w),
        curve(:expected, by_hour) { |hour| scaled(hour.irradiance_w_per_m2) },
        curve(:theory, by_hour) { |hour| scaled(hour.positioned? ? ClearSky.w_per_m2(hour.elevation) : nil) }
      ]
    end

    def curve(key, by_hour, &value)
      points = by_hour.filter_map do |clock, group|
        values = group.filter_map(&value)
        [ clock, values.sum / values.length ] if values.any?
      end

      Curve.new(key: key, points: points)
    end

    def scaled(w_per_m2) = w_per_m2.nil? || @best_ratio.nil? ? nil : w_per_m2 * @best_ratio
  end
end
