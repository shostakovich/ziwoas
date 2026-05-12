module Sensors
  class ReadingPresenter
    CO2_WARN_PPM    = 1000
    CO2_BAD_PPM     = 1400
    BATTERY_LOW_PCT = 20
    OFFLINE_AFTER   = 30.minutes

    def initialize(reading, now: Time.current)
      @reading = reading
      @now     = now
    end

    def co2_level
      ppm = @reading&.co2
      return nil if ppm.nil?
      return :bad  if ppm > CO2_BAD_PPM
      return :warn if ppm >= CO2_WARN_PPM
      :good
    end

    def battery_low?
      pct = @reading&.battery_pct
      return false if pct.nil?
      pct <= BATTERY_LOW_PCT
    end

    def age_label
      return "—" if @reading.nil?
      delta = (@now - @reading.taken_at).to_i
      return "vor #{delta} s"       if delta < 60
      return "vor #{delta / 60} Min" if delta < 3600
      "vor #{delta / 3600} h"
    end

    def offline?
      return true if @reading.nil?
      (@now - @reading.taken_at) > OFFLINE_AFTER
    end
  end
end
