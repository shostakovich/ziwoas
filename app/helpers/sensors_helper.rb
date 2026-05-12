# app/helpers/sensors_helper.rb
module SensorsHelper
  CO2_WARN_PPM    = Sensors::ReadingPresenter::CO2_WARN_PPM
  CO2_BAD_PPM     = Sensors::ReadingPresenter::CO2_BAD_PPM
  BATTERY_LOW_PCT = Sensors::ReadingPresenter::BATTERY_LOW_PCT

  def co2_level(ppm)
    Sensors::ReadingPresenter.new(SensorReading.new(co2: ppm)).co2_level
  end

  def co2_icon_path(level)
    "co2_#{level}.webp"
  end

  def battery_low?(pct)
    Sensors::ReadingPresenter.new(SensorReading.new(battery_pct: pct)).battery_low?
  end

  def relative_time(time)
    return "—" if time.nil?
    Sensors::ReadingPresenter.new(SensorReading.new(taken_at: time)).age_label
  end
end
