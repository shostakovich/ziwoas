module Economics
  class OverviewCardComponent < ApplicationComponent
    def initialize(result:, title: "Wirtschaftlichkeit", link: true)
      @result = result
      @title = title
      @link = link
    end

    private

    attr_reader :result, :title

    def link? = @link

    def tiles
      [
        [ "Anschaffungs\u00ADkosten", cost_value ],
        [ "Ersparnis", saved_value ],
        [ "Zurückverdient", covered_value ],
        [ payback_label, payback_value ]
      ]
    end

    def subtitle = result.data_start && "seit #{date(result.data_start)}"

    def cost_value = GermanNumber.format(result.acquisition_cost_eur, precision: 2, unit: "€")

    def saved_value
      return GermanNumber::MISSING if result.saved_eur.nil?

      GermanNumber.format(result.saved_eur, precision: 2, unit: "€")
    end

    def covered_value
      return GermanNumber::MISSING if result.covered_ratio.nil?

      GermanNumber.format(result.covered_ratio * 100, precision: 1, unit: "%")
    end

    def covered_pct
      return nil if result.covered_ratio.nil?

      (result.covered_ratio * 100).round
    end

    def payback_label = result.reached? ? "Amortisiert" : "Voraus\u00ADsichtliche Amortisation"

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
  end
end
