module SensorsHelper
  def battery_low?(pct)
    Sensors::ReadingPresenter.new(SensorReading.new(battery_pct: pct)).battery_low?
  end

  def relative_time(time)
    return "—" if time.nil?
    Sensors::ReadingPresenter.new(SensorReading.new(taken_at: time)).age_label
  end
end
