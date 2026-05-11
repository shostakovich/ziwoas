class TrmnlPayloadBuilder
  def initialize(config:)
    @config = config
  end

  def build
    summary = EnergySummary.new(config: @config).compute_today
    pv_kwh     = (summary.produced_wh.to_f / 1000.0).round(2)
    cons_kwh   = (summary.consumed_wh.to_f / 1000.0).round(2)
    bilanz_kwh = (pv_kwh - cons_kwh).round(2)
    autarky    = (summary.autarky_ratio          * 100).round
    self_use   = (summary.self_consumption_ratio * 100).round

    {
      "merge_variables" => {
        "pv_kwh"     => pv_kwh,
        "cons_kwh"   => cons_kwh,
        "bilanz_kwh" => bilanz_kwh,
        "autarky"    => autarky,
        "self_use"   => self_use,
      },
    }
  end
end
