module SunCalendar
  # Sunrise, sunset and solar noon over a whole year, in local clock hours.
  # On a daylight saving change the previous offset's value comes first, so the
  # line steps by one hour where the clock does instead of ramping across it.
  #
  # A location without coordinates has a sun that rises nowhere, so the lines
  # come out empty without a guard of their own.
  class SunLines
    SECONDS_PER_HOUR = 3600
    SECONDS_PER_DAY = 86_400

    def initialize(location:)
      @location = location
    end

    def build(year)
      rise = []
      set = []
      noon = []
      previous_offset = nil

      (Date.new(year, 1, 1)..Date.new(year, 12, 31)).each do |date|
        offset = utc_offset(date)
        seam = previous_offset && previous_offset != offset ? previous_offset : nil
        previous_offset = offset

        events = events(date)
        next if events.nil?

        [ seam, offset ].compact.each do |with_offset|
          first, last = events.map { |time| local_hour(time, with_offset) }
          rise << [ date.yday, first ]
          set << [ date.yday, last ]
          noon << [ date.yday, (first + last) / 2 ]
        end
      end

      Lines.new(rise: rise, set: set, noon: noon)
    end

    private

    # Both events, or nil on a polar day without either — and on every day of a
    # location whose coordinates nobody configured.
    def events(date)
      sunrise = @location.sun.sunrise(date)
      sunset = @location.sun.sunset(date)
      return nil if sunrise.nil? || sunset.nil?

      [ sunrise, sunset ]
    end

    def local_hour(time, offset)
      (time.to_i + offset) % SECONDS_PER_DAY / SECONDS_PER_HOUR.to_f
    end

    # Read at local noon: a change happens at night, so both events of the day
    # already sit on the new offset.
    def utc_offset(date) = @location.timezone.parse("#{date} 12:00").utc_offset
  end
end
