# The smallest unit of the schedule: switch one plug on or off at one time of
# day, on a fixed set of weekdays. Weekdays are absolute — a window running past
# midnight is stored as an on rule and an off rule on the following days, so
# nothing here needs to know about midnight.
#
# A +group_id+ ties the two halves of a Zeitfenster together for display and
# editing; a rule without one is an Einzelschaltung. The edge calculation never
# looks at the group.
class SwitchRule < ApplicationRecord
  ACTIONS      = %w[on off].freeze
  ISO_DAYS     = (1..7).to_a.freeze
  MINUTE_RANGE = (0..1439)

  before_validation :normalize_days

  validates :plug_id, presence: true
  validates :action, inclusion: { in: ACTIONS }
  validates :at_minute, inclusion: { in: MINUTE_RANGE, message: "muss zwischen 00:00 und 23:59 liegen" }
  validate  :days_are_iso_weekdays

  scope :enabled, -> { where(enabled: true) }

  def at_minute_time
    return nil if at_minute.nil?
    format("%02d:%02d", at_minute / 60, at_minute % 60)
  end

  def at_minute_time=(str)
    self.at_minute = str.to_s =~ /\A([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\z/ ? Integer($1) * 60 + Integer($2) : nil
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
