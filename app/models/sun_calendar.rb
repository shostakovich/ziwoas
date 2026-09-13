# One calendar year of PV power, irradiance and cloud cover, laid out as day
# columns over local clock hours — the sun calendar on the reports page.
module SunCalendar
  # Clock hours every strip shows; widened when data falls outside.
  BASE_HOURS = (3..22).freeze

  # A strip's cells, keyed by [day of year, local clock hour].
  Strip = Data.define(:key, :title, :unit, :ramp, :max, :values) do
    def empty? = values.empty?
  end

  # Per-day totals behind the bars and the tooltip. Any of the numbers is nil
  # when that day has no data.
  Day = Data.define(:doy, :date, :pv_kwh, :irradiance_kwh_per_m2, :cloud_avg)

  # The sun's daily events over the year, as [day of year, local hour] points.
  Lines = Data.define(:rise, :set, :noon) do
    def empty? = rise.empty?
  end

  # `seam` is the first day the inverter reported, on a year where the
  # producer plug stood in before it; nil when nothing changed hands.
  Year = Data.define(:year, :days, :hours, :strips, :max_kwh, :lines, :seam) do
    # The section stands or falls with the PV hours; the weather strips only
    # give them context.
    def empty? = strips.fetch(:pv).empty?
  end
end
