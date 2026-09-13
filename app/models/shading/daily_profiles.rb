module Shading
  # The day's shape per month, as three curves over the same clock hours: what
  # the array made, what the measured irradiance promised, and what a cloudless
  # sky would have offered. The latter two are converted with the best hour's
  # ratio, so all three read in watts and the distance between them is the
  # share that shading, orientation or curtailment cost.
  class DailyProfiles
    KEYS = %i[measured expected theory].freeze

    def initialize(best_ratio:)
      @best_ratio = best_ratio
    end

    def build(hours)
      hours.group_by { |hour| hour.time.month }.sort.map do |month, group|
        Profile.new(month: month, days: group.map(&:date).uniq.length, curves: Shading.trim(curves(group)))
      end
    end

    private

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
