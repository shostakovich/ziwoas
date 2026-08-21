class ApiController < ApplicationController
  def today
    end_ts   = Time.now.to_i
    start_ts = ((end_ts - 86_400) / 3600) * 3600

    rows_by_plug = Sample.where(ts: start_ts..(end_ts - 1))
                         .group(:plug_id, Arel.sql("(ts / 60) * 60"))
                         .select("plug_id, (ts / 60) * 60 AS minute_ts, AVG(apower_w) AS avg_power_w")
                         .group_by(&:plug_id)

    @series = app_config.plugs.map do |plug|
      points = (rows_by_plug[plug.id] || [])
        .map { |r| { ts: r.minute_ts, avg_power_w: r.avg_power_w.to_f } }
        .sort_by { |p| p[:ts] }
      { plug_id: plug.id, name: plug.name, role: plug.role, points: points }
    end
  end

  def today_summary
    @summary = EnergySummary.new(config: app_config).compute_today
  end

  def history
    @days   = (params["days"] || "14").to_i.clamp(1, 365)
    cutoff = (Date.today - @days).to_s

    rows_by_plug = DailyTotal.where("date >= ?", cutoff).order(:date).group_by(&:plug_id)

    @series = app_config.plugs.map do |plug|
      points = (rows_by_plug[plug.id] || [])
                   .map { |r| { date: r.date, energy_wh: r.energy_wh } }
      { plug_id: plug.id, name: plug.name, role: plug.role, points: points }
    end
  end

  def live
    @now_ts = Time.now.to_i
    config  = app_config
    now     = Time.zone.at(@now_ts)
    solakon = config.solakon

    measurements = PlugMeasurement.for(config.plugs.map(&:id), now: now)

    @plugs = config.plugs.map do |plug|
      measurement = measurements[plug.id]
      {
        id:           plug.id,
        name:         plug.name,
        role:         plug.role,
        online:       !measurement.offline?,
        apower_w:     measurement.offline? ? nil : measurement.watt,
        last_seen_ts: measurement.last_seen_at&.to_i
      }
    end

    consumer_ids = config.plugs.select { |plug| plug.role == :consumer }.map(&:id)
    reading = if solakon&.monitoring_enabled
      SolakonReading.latest_fresh(now: now)
    end

    @energy_flow = EnergyFlow.build(home_w: measurements.total_w(consumer_ids), reading: reading)
  end
end
