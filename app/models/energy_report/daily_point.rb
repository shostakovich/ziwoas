class EnergyReport
  # One day of the report, in Wh. Uncovered days have no aggregate behind them.
  class DailyPoint < Dry::Struct
    module Types
      include Dry.Types()
    end

    attribute :date,          Types::Strict::String
    attribute :produced,      Energy
    attribute :consumed,      Energy
    attribute :self_consumed, Energy
    attribute :covered,       Types::Strict::Bool

    def self.uncovered(date_s)
      new(date: date_s, produced: Energy.zero, consumed: Energy.zero,
          self_consumed: Energy.zero, covered: false)
    end

    def balance = produced - consumed
  end
end
