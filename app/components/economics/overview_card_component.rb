module Economics
  # The Wirtschaftlichkeit card on the PV page: what the plant cost, what it has
  # saved since the data start, and when the two meet. Every figure that cannot
  # be had honestly is shown as an em dash with the reason next to it.
  class OverviewCardComponent < ApplicationComponent
    def initialize(result:)
      @result = result
    end

    private

    attr_reader :result

    def subtitle = result.data_start && "seit #{date(result.data_start)}"

    def cost_value = euro(result.acquisition_cost_eur)

    def saved_value = result.saved_eur.nil? ? "—" : euro(result.saved_eur)

    def covered_value
      return "—" if result.covered_ratio.nil?

      "#{number(result.covered_ratio * 100, precision: 1)} %"
    end

    def covered_pct
      return nil if result.covered_ratio.nil?

      (result.covered_ratio * 100).round
    end

    def payback_label = result.reached? ? "Amortisiert" : "Voraussichtliche Amortisation"

    def payback_value
      return date(result.reached_on) if result.reached?
      return date(result.projected_payback_date) if result.projected_payback_date

      short_of_data? ? "Noch zu wenig Daten" : "—"
    end

    def short_of_data?
      result.priced? && result.costed? && result.projection_days < Payback::MIN_PROJECTION_DAYS
    end

    def hint
      return "Noch kein Strompreis erfasst." unless result.priced?
      return "Noch keine Kosten erfasst." unless result.costed?
      return "Hochrechnung aus #{result.projection_days} Tagen." if result.projected_payback_date

      "Basis sind erst #{result.projection_days} Tage." if short_of_data?
    end

    def date(value) = I18n.l(value, format: "%d.%m.%Y")

    def euro(value) = "#{number(value)} €"

    def number(value, precision: 2)
      ActiveSupport::NumberHelper.number_to_rounded(
        value, precision: precision, separator: ",", delimiter: "."
      )
    end
  end
end
