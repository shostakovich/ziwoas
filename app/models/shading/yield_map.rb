module Shading
  # The sky cut into fields of a few degrees: every hour lands where the sun
  # stood, and a field keeps the median of its hours. The median, not the mean,
  # because a single cloud passing through must not lift a field that is in
  # shadow every day.
  class YieldMap
    BIN_SIZE_DEG = 5
    # Below this the station measured little more than the sky's glow, and the
    # ratio of two small numbers says nothing.
    MIN_IRRADIANCE_W_PER_M2 = 100
    # A field speaks only once it has been visited on several days.
    MIN_HOURS = 3

    def initialize(best_ratio:)
      @best_ratio = best_ratio
    end

    def build(hours, paths)
      Map.new(bins: bins(hours), paths: paths, bin_size: BIN_SIZE_DEG)
    end

    private

    def bins(hours)
      return [] if @best_ratio.nil?

      grouped(hours).filter_map do |(azimuth, elevation), group|
        next if group.length < MIN_HOURS

        clocks = group.map { |hour| hour.time.hour }
        Bin.new(
          azimuth: azimuth, elevation: elevation,
          share: median(group.map(&:ratio)) / @best_ratio,
          hours: group.length, first_hour: clocks.min, last_hour: clocks.max
        )
      end
    end

    def grouped(hours)
      hours.select { |hour| measured?(hour) }
           .group_by { |hour| [ snap(hour.azimuth), snap(hour.elevation) ] }
    end

    def measured?(hour)
      !hour.ratio.nil? && hour.irradiance_w_per_m2 >= MIN_IRRADIANCE_W_PER_M2 &&
        hour.positioned? && hour.elevation > 0
    end

    def snap(degrees) = (degrees / BIN_SIZE_DEG).floor * BIN_SIZE_DEG

    def median(values)
      sorted = values.sort
      middle = sorted.length / 2
      sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end
  end
end
