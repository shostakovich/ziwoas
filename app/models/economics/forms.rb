module Economics
  # The dry boundary for the two lists: what a human typed becomes a checked
  # amount and a checked date before it reaches a record.
  module Forms
    MESSAGES = {
      label:  "Bezeichnung angeben",
      amount: "Betrag als Zahl angeben",
      date:   "Datum angeben",
      price:  "Preis muss größer als 0 sein"
    }.freeze

    def self.date?(value)
      Date.iso8601(value.to_s)
      true
    rescue ArgumentError, TypeError
      false
    end
  end
end
