# The smallest unit of the schedule: switch one plug on or off at one time of
# day, on a fixed set of weekdays. A +group_id+ ties the two halves of a
# Zeitfenster together for display and editing; a rule without one is an
# Einzelschaltung. The edge calculation never looks at the group.
class SwitchRule < ApplicationRecord
  ACTIONS      = %w[on off].freeze
  ISO_DAYS     = (1..7).to_a.freeze
  MINUTE_RANGE = (0..1439)
  CLOCK_TIME   = /\A([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\z/

  # "18:00" -> 1080, anything else -> nil. Base 10 spelled out: "08" carries a
  # leading zero, which Integer() would otherwise read as an octal prefix and
  # reject.
  def self.minutes_from(str)
    m = CLOCK_TIME.match(str.to_s) or return nil
    Integer(m[1], 10) * 60 + Integer(m[2], 10)
  end

  before_validation :normalize_days

  validates :plug_id, presence: true
  validates :action, inclusion: { in: ACTIONS }
  validates :at_minute, inclusion: { in: MINUTE_RANGE, message: "muss zwischen 00:00 und 23:59 liegen" }
  validate  :days_are_iso_weekdays

  scope :enabled, -> { where(enabled: true) }

  # True while the group still holds both halves. Such a rule belongs to the
  # Zeitfenster and may only be touched together with its partner.
  def half_of_a_window?
    group_id.present? && self.class.where(group_id: group_id).count == 2
  end

  def at_minute_time
    return nil if at_minute.nil?
    format("%02d:%02d", at_minute / 60, at_minute % 60)
  end

  def at_minute_time=(str)
    self.at_minute = self.class.minutes_from(str)
  end

  private

  def normalize_days
    return unless days.is_a?(Array)
    self.days = days.reject { |d| d.to_s.strip.empty? }.map(&:to_i).uniq.sort
  end

  def days_are_iso_weekdays
    unless days.is_a?(Array) && days.any? && days.all? { |d| ISO_DAYS.include?(d) }
      errors.add(:days, "mindestens ein Wochentag muss gewählt sein")
    end
  end
end
