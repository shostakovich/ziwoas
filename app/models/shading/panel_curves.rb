module Shading
  # The four panels beside each other over the day. A panel that is not yet
  # wired reports zero all day long rather than going absent, so only days on
  # which every panel delivered at least once are counted — otherwise the two
  # younger panels would drag their own curve down through months they never
  # saw.
  class PanelCurves
    KEYS = %i[pv1 pv2 pv3 pv4].freeze

    def build(hours)
      days = countable(hours)
      Panels.new(curves: Shading.trim(curves(days.values.flatten)), days: days.length, since: days.keys.min)
    end

    private

    def countable(hours)
      hours.select { |hour| hour.panels.length == KEYS.length && hour.panels.none?(&:nil?) }
           .group_by(&:date)
           .select { |_date, group| all_delivered?(group) }
    end

    def all_delivered?(hours)
      KEYS.each_index.all? { |index| hours.any? { |hour| hour.panels[index] > 0 } }
    end

    def curves(hours)
      by_hour = hours.group_by { |hour| hour.time.hour }.sort

      KEYS.each_with_index.map do |key, index|
        points = by_hour.map do |clock, group|
          watts = group.map { |hour| hour.panels[index] }
          [ clock, watts.sum / watts.length ]
        end

        Curve.new(key: key, points: points)
      end
    end
  end
end
