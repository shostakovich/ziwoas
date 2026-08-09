require "test_helper"
require "config_loader"

class SwitchRowTest < ActiveSupport::TestCase
  setup do
    Sample.delete_all
    PlugState.delete_all
    SwitchCommand.delete_all
    SwitchRule.delete_all
    @plug = ConfigLoader::PlugCfg.new(id: "fridge", name: "Kühlschrank", role: :consumer,
                                      driver: :shelly, ain: nil, switchable: true)
  end

  # One Zeitfenster: two rules of one group, 18:00-23:00 on Mondays.
  def window(plug_id: "fridge", on_at: 1080, off_at: 1380, days: [ 1 ], enabled: true)
    group = SecureRandom.uuid
    [
      SwitchRule.create!(plug_id: plug_id, action: "on",  at_minute: on_at,  days: days, enabled: enabled, group_id: group),
      SwitchRule.create!(plug_id: plug_id, action: "off", at_minute: off_at, days: days, enabled: enabled, group_id: group)
    ]
  end

  test "build collects state, last command, entries, watt and next edge" do
    travel_to Time.zone.local(2026, 6, 15, 17, 0) do  # Monday
      PlugState.record_output("fridge", true)
      SwitchCommand.create!(plug_id: "fridge", action: "on", source: "schedule")
      window
      Sample.create!(plug_id: "fridge", ts: Time.current.to_i - 30, apower_w: 42.0, aenergy_wh: 1.0)

      row = SwitchRow.build(@plug)
      assert row.on?
      refute row.offline?
      assert_in_delta 42.0, row.watt
      assert_equal 1, row.entries.size
      assert_equal :on, row.next_edge.action
      assert_equal Time.zone.local(2026, 6, 15, 18, 0), row.next_edge.at
      assert_equal "on", row.last_command.action
    end
  end

  test "offline when last sample is older than 5 minutes or missing" do
    travel_to Time.zone.local(2026, 6, 15, 17, 0) do
      assert SwitchRow.build(@plug).offline?
      Sample.create!(plug_id: "fridge", ts: 6.minutes.ago.to_i, apower_w: 1.0, aenergy_wh: 1.0)
      assert SwitchRow.build(@plug).offline?
      Sample.create!(plug_id: "fridge", ts: 4.minutes.ago.to_i, apower_w: 1.0, aenergy_wh: 1.0)
      refute SwitchRow.build(@plug).offline?
    end
  end

  test "on? falls back to last command without plug state, default off" do
    refute SwitchRow.build(@plug).on?
    SwitchCommand.create!(plug_id: "fridge", action: "on", source: "manual")
    assert SwitchRow.build(@plug).on?
  end

  test "on? lets a manual command fresher than the plug state win" do
    travel_to Time.zone.local(2026, 6, 15, 17, 0) do
      PlugState.record_output("fridge", false)
    end
    travel_to Time.zone.local(2026, 6, 15, 17, 5) do
      SwitchCommand.create!(plug_id: "fridge", action: "on", source: "manual")
      assert SwitchRow.build(@plug).on?
    end
    # Device confirms afterwards: plug state is fresher again and wins.
    travel_to Time.zone.local(2026, 6, 15, 17, 6) do
      PlugState.find_by(plug_id: "fridge").touch
      refute SwitchRow.build(@plug).on?
    end
  end

  test "paused rules do not produce a next edge" do
    travel_to Time.zone.local(2026, 6, 15, 17, 0) do
      window(enabled: false)
      row = SwitchRow.build(@plug)
      assert_nil row.next_edge
      refute row.schedule?
      assert_equal 1, row.entries.size  # still listed for editing
    end
  end

  test "an Einzelschaltung shows up as its own entry" do
    travel_to Time.zone.local(2026, 6, 15, 17, 0) do
      SwitchRule.create!(plug_id: "fridge", action: "off", at_minute: 1320, days: [ 1 ])
      row = SwitchRow.build(@plug)
      assert_equal 1, row.entries.size
      assert_equal :off, row.next_edge.action
      assert row.schedule?
    end
  end

  test "adjoining windows announce the on edge, like the tick performs it" do
    travel_to Time.zone.local(2026, 6, 15, 9, 0) do  # Monday
      window(on_at: 360, off_at: 600)   # 06:00-10:00
      window(on_at: 600, off_at: 840)   # 10:00-14:00
      row = SwitchRow.build(@plug)
      assert_equal Time.zone.local(2026, 6, 15, 10, 0), row.next_edge.at
      assert_equal :on, row.next_edge.action
    end
  end

  test "entries of one plug are folded and sorted, other plugs stay out" do
    travel_to Time.zone.local(2026, 6, 15, 17, 0) do
      late   = SwitchRule.create!(plug_id: "fridge", action: "off", at_minute: 1320, days: [ 1 ])
      early, = window(on_at: 360, off_at: 600)
      window(plug_id: "other")

      row = SwitchRow.build(@plug)
      assert_equal [ early.group_id, late.id ], row.entries.map(&:id)
    end
  end

  test "build_all returns same rows as individual build" do
    travel_to Time.zone.local(2026, 6, 15, 17, 0) do
      plug_a = ConfigLoader::PlugCfg.new(id: "a", name: "A", role: :consumer,
                                          driver: :shelly, ain: nil, switchable: true)
      plug_b = ConfigLoader::PlugCfg.new(id: "b", name: "B", role: :consumer,
                                          driver: :shelly, ain: nil, switchable: true)
      window(plug_id: "a")
      window(plug_id: "b", on_at: 300, off_at: 900)
      plugs = [ plug_a, plug_b ]
      all   = SwitchRow.build_all(plugs, now: Time.current)
      singles = plugs.map { |p| SwitchRow.build(p, now: Time.current) }
      assert_equal singles.map(&:on?),       all.map(&:on?)
      assert_equal singles.map(&:offline?),  all.map(&:offline?)
      assert_equal singles.map { |r| r.entries.map(&:id) }, all.map { |r| r.entries.map(&:id) }
    end
  end
end
