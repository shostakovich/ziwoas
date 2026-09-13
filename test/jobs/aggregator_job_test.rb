require "test_helper"
require "tmpdir"

class AggregatorJobTest < ActiveJob::TestCase
  cover "AggregatorJob*"

  self.use_transactional_tests = false

  class RecordingAggregator
    attr_reader :today, :backup_dir

    def run_once(today:) = (@today = today)
    def backup!(backup_dir) = (@backup_dir = backup_dir)
  end

  class RecordingPvHourAggregator
    attr_reader :today

    def run_once(today:) = (@today = today)
  end

  setup do
    Plugs::Sample.delete_all
    Plugs::Sample5min.delete_all
    Plugs::DailyTotal.delete_all
    Solakon::Reading.delete_all
    Solakon::PvHour.delete_all
    DailyEnergySummary.delete_all
  end

  test "aggregates finished days and writes a backup" do
    tz = TZInfo::Timezone.get("Europe/Berlin")
    start_ts = tz.local_to_utc(Time.parse("2026-04-10 00:00:00")).to_i

    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts, apower_w: 10, aenergy_wh: 100)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 3600, apower_w: 10, aenergy_wh: 150)

    Dir.mktmpdir do |backup_dir|
      AggregatorJob.perform_now(today: Date.new(2026, 4, 11), backup_dir: backup_dir)

      total = Plugs::DailyTotal.find_by!(plug_id: "bkw", date: "2026-04-10")
      assert_in_delta 50.0, total.energy_wh
      assert_equal 1, Dir.glob("#{backup_dir}/ziwoas-*.db").length
      assert DailyEnergySummary.exists?(date: "2026-04-10")
    end
  end

  test "condenses the inverter readings of finished days into PV hours" do
    from = Time.zone.local(2026, 4, 10, 12)
    20.times do |i|
      Solakon::Reading.create!(taken_at: from + i * 30, pv_power_w: 300,
                               active_power_w: 0, battery_power_w: 0, battery_soc_pct: 50)
    end

    Dir.mktmpdir do |backup_dir|
      AggregatorJob.perform_now(today: Date.new(2026, 4, 11), backup_dir: backup_dir)
    end

    hour = Solakon::PvHour.sole
    assert_equal from, hour.started_at
    assert_in_delta 300.0, hour.pv_power_w
  end

  test "loads the test config in the test environment" do
    expected_path = Rails.root.join("config", "ziwoas.test.yml").to_s
    config = ConfigLoader::Config.new(location: Location.new(timezone: "Europe/Berlin"))
    original_load = ConfigLoader.method(:load)
    loaded_path = nil
    ConfigLoader.define_singleton_method(:load) do |path|
      loaded_path = path
      config
    end

    Dir.mktmpdir do |backup_dir|
      AggregatorJob.perform_now(today: Date.new(2026, 4, 11), backup_dir: backup_dir)
    end
    assert_equal expected_path, loaded_path
  ensure
    ConfigLoader.define_singleton_method(:load, original_load)
  end

  test "defaults to the configured zone's date and the storage/backup directory, forwarding both to the aggregators" do
    aggregator = RecordingAggregator.new
    pv_hour_aggregator = RecordingPvHourAggregator.new

    # 23:30 UTC is already the next day in Berlin.
    travel_to Time.utc(2026, 4, 10, 23, 30) do
      Aggregator.stub(:new, aggregator) do
        Solakon::PvHourAggregator.stub(:new, pv_hour_aggregator) do
          AggregatorJob.perform_now
        end
      end
    end

    assert_equal Date.new(2026, 4, 11), aggregator.today
    assert_equal Date.new(2026, 4, 11), pv_hour_aggregator.today
    assert_equal Rails.root.join("storage", "backup").to_s, aggregator.backup_dir
  end

  test "builds the aggregator from the configured timezone and plugs" do
    fake_plugs = [ ConfigLoader::PlugCfg.new(id: "bkw", role: :producer) ]
    fake_config = ConfigLoader::Config.new(location: Location.new(timezone: "America/New_York"), plugs: fake_plugs)
    aggregator = RecordingAggregator.new
    captured = nil

    ConfigLoader.stub(:app_config, fake_config) do
      Aggregator.stub(:new, ->(**kwargs) { captured = kwargs; aggregator }) do
        Solakon::PvHourAggregator.stub(:new, RecordingPvHourAggregator.new) do
          AggregatorJob.perform_now(today: Date.new(2026, 4, 11), backup_dir: "/unused")
        end
      end
    end

    assert_equal "America/New_York", ActiveSupport::TimeZone[captured.fetch(:timezone)].name
    assert_equal fake_plugs, captured.fetch(:plugs)
  end
end
