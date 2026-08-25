class ApiController < ApplicationController
  TODAY_BUCKET_SECONDS = 60

  def today
    end_ts   = Time.now.to_i
    start_ts = ((end_ts - 86_400) / 3600) * 3600

    series = PowerSeries.from_samples(plugs: app_config.plugs, start_ts: start_ts, end_ts: end_ts,
                                      bucket_seconds: TODAY_BUCKET_SECONDS)

    @series = app_config.plugs.map do |plug|
      points = series.signed_watts_by_ts(plug.id).map { |ts, watt| { ts: ts, avg_power_w: watt } }
      { plug_id: plug.id, name: plug.name, role: plug.role, points: points }
    end
  end

  def today_summary
    @summary = EnergySummary.new(config: app_config).compute_today
  end

  def history
    @days   = (params["days"] || "14").to_i.clamp(1, 365)
    cutoff = (Date.today - @days).to_s

    rows_by_plug = Plugs::DailyTotal.where("date >= ?", cutoff).order(:date).group_by(&:plug_id)

    @series = app_config.plugs.map do |plug|
      points = (rows_by_plug[plug.id] || [])
                   .map { |r| { date: r.date, energy_wh: r.energy_wh } }
      { plug_id: plug.id, name: plug.name, role: plug.role, points: points }
    end
  end
end
