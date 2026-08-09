require "test_helper"

class SwitchRules::WindowConversionTest < ActiveSupport::TestCase
  TS = Time.zone.local(2026, 6, 1, 9, 30).freeze

  def window(**overrides)
    {
      "plug_id"    => "electrickettle",
      "on_at"      => 360,
      "off_at"     => 1320,
      "days"       => [ 1, 2, 3, 4, 5, 6, 7 ],
      "enabled"    => true,
      "created_at" => TS,
      "updated_at" => TS
    }.merge(overrides.transform_keys(&:to_s))
  end

  def rule(**overrides)
    {
      "plug_id"    => "electrickettle",
      "action"     => "on",
      "at_minute"  => 360,
      "days"       => [ 1, 2, 3, 4, 5, 6, 7 ],
      "enabled"    => true,
      "group_id"   => "g1",
      "created_at" => TS,
      "updated_at" => TS
    }.merge(overrides.transform_keys(&:to_s))
  end

  # --- split ------------------------------------------------------------

  test "a daytime window splits into an on and an off rule sharing a group" do
    on, off = SwitchRules::WindowConversion.split(window)

    assert_equal "on",  on["action"]
    assert_equal "off", off["action"]
    assert_equal 360,   on["at_minute"]
    assert_equal 1320,  off["at_minute"]
    assert_equal "electrickettle", on["plug_id"]
    assert_equal "electrickettle", off["plug_id"]
    assert_equal on["group_id"], off["group_id"]
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, on["group_id"])
  end

  test "each window gets its own group" do
    a, = SwitchRules::WindowConversion.split(window)
    b, = SwitchRules::WindowConversion.split(window)
    refute_equal a["group_id"], b["group_id"]
  end

  test "a daytime window keeps the same days on both rules" do
    on, off = SwitchRules::WindowConversion.split(window(days: [ 1, 2, 3, 4, 5 ]))

    assert_equal [ 1, 2, 3, 4, 5 ], on["days"]
    assert_equal [ 1, 2, 3, 4, 5 ], off["days"]
  end

  test "a midnight crosser shifts the off days one day forward" do
    on, off = SwitchRules::WindowConversion.split(window(on_at: 1320, off_at: 360, days: [ 1, 2, 3, 4, 5 ]))

    assert_equal [ 1, 2, 3, 4, 5 ], on["days"]   # Mo-Fr an
    assert_equal [ 2, 3, 4, 5, 6 ], off["days"]  # Di-Sa aus
  end

  test "a midnight crosser wraps Sunday around to Monday" do
    _on, off = SwitchRules::WindowConversion.split(window(on_at: 1320, off_at: 360, days: [ 6, 7 ]))

    assert_equal [ 1, 7 ], off["days"]           # Sa/So an -> So/Mo aus
  end

  test "a paused window splits into two paused rules" do
    on, off = SwitchRules::WindowConversion.split(window(enabled: false))

    assert_equal false, on["enabled"]
    assert_equal false, off["enabled"]
  end

  test "an orphaned window migrates like any other" do
    on, off = SwitchRules::WindowConversion.split(window(plug_id: "gone"))

    assert_equal "gone", on["plug_id"]
    assert_equal "gone", off["plug_id"]
  end

  test "both rules carry the timestamps of the window" do
    on, off = SwitchRules::WindowConversion.split(window)

    assert_equal TS, on["created_at"]
    assert_equal TS, off["updated_at"]
  end

  # --- join -------------------------------------------------------------

  test "a complete group joins back into one window" do
    windows = SwitchRules::WindowConversion.join([
      rule(action: "on",  at_minute: 360),
      rule(action: "off", at_minute: 1320)
    ])

    assert_equal 1, windows.size
    assert_equal 360,  windows.first["on_at"]
    assert_equal 1320, windows.first["off_at"]
    assert_equal "electrickettle", windows.first["plug_id"]
    assert_equal [ 1, 2, 3, 4, 5, 6, 7 ], windows.first["days"]
    assert_equal true, windows.first["enabled"]
    assert_equal TS, windows.first["created_at"]
  end

  test "a joined group takes the days of its on rule, undoing the shift" do
    windows = SwitchRules::WindowConversion.join([
      rule(action: "on",  at_minute: 1320, days: [ 1, 2, 3, 4, 5 ]),
      rule(action: "off", at_minute: 360,  days: [ 2, 3, 4, 5, 6 ])
    ])

    assert_equal [ 1, 2, 3, 4, 5 ], windows.first["days"]
  end

  test "a paused group joins into a paused window" do
    windows = SwitchRules::WindowConversion.join([
      rule(action: "on",  enabled: false),
      rule(action: "off", enabled: false)
    ])

    assert_equal false, windows.first["enabled"]
  end

  test "a groupless single rule is dropped" do
    windows = SwitchRules::WindowConversion.join([
      rule(action: "off", group_id: nil),
      rule(action: "on",  group_id: nil)
    ])

    assert_empty windows
  end

  test "a half group is dropped rather than joined" do
    windows = SwitchRules::WindowConversion.join([ rule(action: "on", group_id: "lonely") ])

    assert_empty windows
  end

  test "a group of two rules pointing the same way is dropped" do
    windows = SwitchRules::WindowConversion.join([
      rule(action: "on", group_id: "twice"),
      rule(action: "on", group_id: "twice", at_minute: 400)
    ])

    assert_empty windows
  end

  test "groups are joined independently of each other" do
    windows = SwitchRules::WindowConversion.join([
      rule(group_id: "a", action: "on",  at_minute: 360),
      rule(group_id: "b", action: "on",  at_minute: 300, plug_id: "senseo"),
      rule(group_id: "a", action: "off", at_minute: 1320),
      rule(group_id: "b", action: "off", at_minute: 1140, plug_id: "senseo"),
      rule(group_id: nil, action: "off", at_minute: 1380)
    ])

    assert_equal [ "electrickettle", "senseo" ], windows.map { |w| w["plug_id"] }.sort
  end

  test "an empty list joins into no windows" do
    assert_empty SwitchRules::WindowConversion.join([])
  end

  # --- round trip -------------------------------------------------------

  test "splitting and joining a midnight crosser returns the original window" do
    original = window(on_at: 1320, off_at: 360, days: [ 1, 2, 3, 4, 5 ])
    rebuilt  = SwitchRules::WindowConversion.join(SwitchRules::WindowConversion.split(original)).first

    assert_equal original, rebuilt.slice(*original.keys)
  end
end
