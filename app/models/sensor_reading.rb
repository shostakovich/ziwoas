class SensorReading < ApplicationRecord
  scope :for_device, ->(id) { where(device_id: id) }
  scope :since,      ->(t)  { where("taken_at >= ?", t) }

  def self.latest_per_device(device_ids)
    return none if device_ids.blank?
    where(device_id: device_ids)
      .where("taken_at = (SELECT MAX(taken_at) FROM sensor_readings sr2
                          WHERE sr2.device_id = sensor_readings.device_id)")
  end
end
