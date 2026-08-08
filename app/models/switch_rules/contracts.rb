module SwitchRules
  # The dry boundary sits at the form, not at the record: the interesting checks
  # span fields ("bis" must differ from "von", at least one weekday), and a
  # single SwitchRule knows nothing about "bis". The Active Record validations
  # stay on SwitchRule as the last line of defence for the console and the
  # migration.
  #
  # All messages are German and spelled out here rather than in a locale file,
  # because they are the only messages these two contracts ever produce.
  module Contracts
    MESSAGES = {
      time:   "Uhrzeit im Format HH:MM angeben",
      days:   "mindestens ein Wochentag muss gewählt sein",
      same:   "An- und Aus-Zeit müssen sich unterscheiden",
      action: "Richtung muss an oder aus sein"
    }.freeze

    # Weekdays arrive from checkboxes, so the set is either complete and valid
    # or the human ticked nothing at all.
    def self.weekdays?(days)
      days.is_a?(Array) && days.any? && days.all? { |d| SwitchRule::ISO_DAYS.include?(d) }
    end
  end
end
