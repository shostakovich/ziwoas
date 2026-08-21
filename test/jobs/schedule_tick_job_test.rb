require "test_helper"

class ScheduleTickJobTest < ActiveSupport::TestCase
  setup do
    Switching::SchedulerState.delete_all
    Switching::Rule.delete_all
    Switching::Command.delete_all
    @calls = []
    @recorder = ->(plug, action, source:, mqtt_config:) { @calls << [ plug.id, action, source ] }
  end

  def monday_18_05 = Time.zone.local(2026, 6, 15, 18, 5)

  def create_rule(action:, at_minute:, days: [ 1 ], plug_id: "fridge", enabled: true)
    Switching::Rule.create!(plug_id: plug_id, action: action.to_s, at_minute: at_minute,
                       days: days, enabled: enabled)
  end

  # A Zeitfenster is two rules now; the job only ever sees the flat rules.
  def create_window(on_at: 1080, off_at: 1380, days: [ 1 ], plug_id: "fridge", enabled: true)
    [ create_rule(action: :on,  at_minute: on_at,  days: days, plug_id: plug_id, enabled: enabled),
      create_rule(action: :off, at_minute: off_at, days: days, plug_id: plug_id, enabled: enabled) ]
  end

  # These two pin the width of the grace window from the no-watermark side.
  # The edge that actually proves edges lapse is the ancient-watermark one below.
  test "without a watermark an edge nine minutes old still fires" do
    create_window(on_at: 1076, off_at: 1380)  # on edge at 17:56, nine minutes old
    travel_to monday_18_05 do
      Switching::Commander.stub :switch, @recorder do
        ScheduleTickJob.perform_now
      end
      assert_equal [ [ "fridge", :on, :schedule ] ], @calls
      assert_equal Time.current, Switching::SchedulerState.last_tick_at("fridge")
    end
  end

  test "without a watermark an edge eleven minutes old does not fire" do
    create_window(on_at: 1074, off_at: 1380)  # on edge at 17:54, eleven minutes old
    travel_to monday_18_05 do
      Switching::Commander.stub :switch, @recorder do
        ScheduleTickJob.perform_now
      end
      assert_empty @calls
      assert_equal Time.current, Switching::SchedulerState.last_tick_at("fridge")
    end
  end

  test "an edge older than the grace window lapses despite an ancient watermark" do
    create_window(on_at: 600, off_at: 1380)  # Mo 10:00-23:00, on edge at 10:00
    travel_to monday_18_05 do
      Switching::SchedulerState.advance!("fridge", 9.hours.ago)  # 09:05, i.e. before the 10:00 edge
      Switching::Commander.stub :switch, @recorder do
        ScheduleTickJob.perform_now
      end
      assert_empty @calls
      assert_equal Time.current, Switching::SchedulerState.last_tick_at("fridge")
    end
  end

  test "fires the edge between watermark and now and advances the watermark" do
    create_window  # Mo 18:00-23:00, on edge at 18:00
    travel_to monday_18_05 do
      Switching::SchedulerState.advance!("fridge", 10.minutes.ago)
      Switching::Commander.stub :switch, @recorder do
        ScheduleTickJob.perform_now
      end
      assert_equal [ [ "fridge", :on, :schedule ] ], @calls
      assert_equal Time.current, Switching::SchedulerState.last_tick_at("fridge")
    end
  end

  test "collapses multiple missed edges to the latest per plug" do
    create_window(on_at: 1080, off_at: 1083)  # Mo 18:00-18:03 -> on@18:00, off@18:03
    travel_to monday_18_05 do
      Switching::SchedulerState.advance!("fridge", 10.minutes.ago)
      Switching::Commander.stub :switch, @recorder do
        ScheduleTickJob.perform_now
      end
      assert_equal [ [ "fridge", :off, :schedule ] ], @calls
    end
  end

  test "skips the edge when a manual command came after the edge time" do
    create_window  # on edge 18:00
    travel_to monday_18_05 do
      Switching::Command.create!(plug_id: "fridge", action: "off", source: "manual",
                            created_at: Time.zone.local(2026, 6, 15, 18, 1))
      Switching::SchedulerState.advance!("fridge", 10.minutes.ago)
      Switching::Commander.stub :switch, @recorder do
        ScheduleTickJob.perform_now
      end
      assert_empty @calls
      assert_equal Time.current, Switching::SchedulerState.last_tick_at("fridge")
    end
  end

  test "ignores disabled rules and rules of unknown plugs" do
    create_window(enabled: false)
    create_window(plug_id: "gone")
    travel_to monday_18_05 do
      Switching::SchedulerState.advance!("fridge", 10.minutes.ago)
      Switching::Commander.stub :switch, @recorder do
        ScheduleTickJob.perform_now
      end
    end
    assert_empty @calls
    assert_nil Switching::SchedulerState.last_tick_at("gone")
  end

  test "advances the watermark of a switchable plug without any rule" do
    travel_to monday_18_05 do
      Switching::Commander.stub :switch, @recorder do
        ScheduleTickJob.perform_now
      end
      assert_empty @calls
      assert_equal Time.current, Switching::SchedulerState.last_tick_at("fridge")
    end
  end

  test "watermark stays put when a publish fails" do
    create_window
    failing = ->(*, **) { raise Switching::Commander::Error, "broker down" }
    travel_to monday_18_05 do
      watermark = 10.minutes.ago
      Switching::SchedulerState.advance!("fridge", watermark)
      Switching::Commander.stub :switch, failing do
        ScheduleTickJob.perform_now
      end
      assert_equal watermark, Switching::SchedulerState.last_tick_at("fridge")
    end
  end

  test "a failed plug retries alone while the others advance" do
    create_window(plug_id: "fridge")
    create_window(plug_id: "senseo")
    flaky = lambda do |plug, action, source:, mqtt_config:|
      raise Switching::Commander::Error, "broker down" if plug.id == "senseo"
      @calls << [ plug.id, action, source ]
    end

    travel_to monday_18_05 do
      watermark = 10.minutes.ago
      Switching::SchedulerState.advance!("fridge", watermark)
      Switching::SchedulerState.advance!("senseo", watermark)
      stub_two_switchable_plugs do
        Switching::Commander.stub :switch, flaky do
          ScheduleTickJob.perform_now
        end
      end

      assert_equal [ [ "fridge", :on, :schedule ] ], @calls
      assert_equal Time.current, Switching::SchedulerState.last_tick_at("fridge")
      assert_equal watermark,    Switching::SchedulerState.last_tick_at("senseo")

      # Second tick: only senseo is still due, fridge has moved past its edge.
      @calls.clear
      stub_two_switchable_plugs do
        Switching::Commander.stub :switch, @recorder do
          ScheduleTickJob.perform_now
        end
      end
      assert_equal [ [ "senseo", :on, :schedule ] ], @calls
    end
  end

  test "the error log names the failing rule" do
    rule = create_window.first
    failing = ->(*, **) { raise Switching::Commander::Error, "broker down" }
    travel_to monday_18_05 do
      Switching::SchedulerState.advance!("fridge", 10.minutes.ago)
      log = capture_log do
        Switching::Commander.stub :switch, failing do
          ScheduleTickJob.perform_now
        end
      end
      assert_match(/fridge/, log)
      assert_match(/rule #{rule.id}/, log)
      assert_match(/broker down/, log)
    end
  end

  private

  def stub_two_switchable_plugs(&block)
    config = ConfigLoader.app_config
    plugs  = config.plugs + [ ConfigLoader::PlugCfg.new(id: "senseo", name: "Senseo", role: :consumer,
                                                        driver: :shelly, ain: nil, switchable: true) ]
    ConfigLoader.stub :app_config, config.dup.tap { |c| c.plugs = plugs }, &block
  end

  def capture_log
    io  = StringIO.new
    old = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = old
  end
end
