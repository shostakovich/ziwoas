require "payback"
require "savings_calculator"

module Economics
  # Everything the Wirtschaftlichkeit card shows, read once: the daily
  # self-consumption on record, priced day by day, against what the plant cost.
  class Overview
    Result = Data.define(
      :saved_eur, :acquisition_cost_eur, :covered_ratio, :data_start,
      :projected_payback_date, :reached_on, :projection_days, :priced?, :costed?
    ) do
      def reached? = !reached_on.nil?
    end

    def initialize(today: Date.current)
      @today = today
    end

    def build
      calculator = SavingsCalculator.new(price_book: ElectricityPrice.book)
      daily      = daily_savings(calculator)
      payback    = Payback.new(acquisition_cost_eur: CostItem.total_eur, daily_savings: daily, today: @today)

      Result.new(
        saved_eur:              calculator.priced? ? payback.saved_eur : nil,
        acquisition_cost_eur:   CostItem.total_eur,
        covered_ratio:          calculator.priced? ? payback.covered_ratio : nil,
        data_start:             first_date,
        projected_payback_date: calculator.priced? ? payback.projected_date : nil,
        reached_on:             calculator.priced? ? payback.reached_on : nil,
        projection_days:        payback.projection_days,
        priced?:                calculator.priced?,
        costed?:                payback.costed?
      )
    end

    private

    def summaries = @summaries ||= DailyEnergySummary.order(:date).to_a

    def first_date
      value = summaries.first&.date
      value && Date.iso8601(value)
    end

    def daily_savings(calculator)
      return [] unless calculator.priced?

      summaries.map do |row|
        date = Date.iso8601(row.date)
        [ date, calculator.savings_eur(Energy.wh(row.self_consumed_wh), on: date) ]
      end
    end
  end
end
