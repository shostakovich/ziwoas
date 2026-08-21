module Switching
  module Rules
    # The dry boundary sits at the form, not at the record: the interesting checks
    # span fields ("bis" must differ from "von", at least one weekday), and a
    # single Switching::Rule knows nothing about "bis". The Active Record validations
    # stay on Switching::Rule as the last line of defence.
    module Contracts
      MESSAGES = {
        time:   "Uhrzeit im Format HH:MM angeben",
        days:   "mindestens ein Wochentag muss gewählt sein",
        same:   "An- und Aus-Zeit müssen sich unterscheiden",
        action: "Richtung muss an oder aus sein"
      }.freeze

      def self.weekdays?(days)
        days.is_a?(Array) && days.any? && days.all? { |d| Switching::Rule::ISO_DAYS.include?(d) }
      end
    end
  end
end
