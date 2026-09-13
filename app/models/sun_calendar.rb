module SunCalendar
  BASE_HOURS = (3..22).freeze

  # `values` is keyed by [day of year, local clock hour].
  Strip = Data.define(:key, :title, :unit, :ramp, :max, :values) do
    def empty? = values.empty?
  end

  Day = Data.define(:doy, :date, :pv_kwh, :irradiance_kwh_per_m2, :cloud_avg)

  # Points are [day of year, local hour].
  Lines = Data.define(:rise, :set, :noon) do
    def empty? = rise.empty?
  end

  Year = Data.define(:year, :days, :hours, :strips, :max_kwh, :lines, :seam) do
    def empty? = strips.fetch(:pv).empty?
  end
end
