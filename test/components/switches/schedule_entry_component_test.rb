require "test_helper"

class Switches::ScheduleEntryComponentTest < ViewComponent::TestCase
  PLUG = ConfigLoader::PlugCfg.new(id: "fridge", name: "Kühlschrank", role: :consumer,
                                   driver: :shelly, ain: nil, room: nil, switchable: true).freeze

  # Rules built in memory, with the ids the row and the button targets are made
  # of — nothing here needs a database.
  def rule(id:, action:, at_minute:, days: [ 1, 2, 3, 4, 5 ], enabled: true, group_id: nil)
    SwitchRule.new(id: id, plug_id: "fridge", action: action, at_minute: at_minute,
                   days: days, enabled: enabled, group_id: group_id)
  end

  def window(enabled: true, group_id: "g-1")
    SwitchRules::Schedule::Window.new(
      on:  rule(id: 1, action: "on",  at_minute: 600,  enabled: enabled, group_id: group_id),
      off: rule(id: 2, action: "off", at_minute: 1200, enabled: enabled, group_id: group_id)
    )
  end

  def single(action: "off", enabled: true)
    SwitchRules::Schedule::Single.new(
      rule: rule(id: 7, action: action, at_minute: 1320, days: SwitchRule::ISO_DAYS, enabled: enabled)
    )
  end

  def render_entry(entry)
    render_inline(Switches::ScheduleEntryComponent.new(entry: entry, plug: PLUG))
  end

  test "a Zeitfenster is one plain pill in a row named by its group" do
    rendered = render_entry(window)

    assert rendered.css("div.sw-entry#sw_entry_fridge_g-1").any?
    assert rendered.css("span.sw-pill").any?
    assert rendered.css("span.sw-pill.single").none?
    assert rendered.css("span.sw-dir").none?
    assert_includes rendered.css("span.sw-pill").text, "Mo–Fr · 10:00–20:00"
  end

  test "an Einzelschaltung is a dashed, directed pill in a row named by its rule" do
    rendered = render_entry(single)

    assert rendered.css("div.sw-entry#sw_entry_fridge_7").any?
    assert rendered.css("span.sw-pill.single").any?
    assert_equal "→ aus", rendered.css("span.sw-pill.single .sw-dir").text
    assert_includes rendered.css("span.sw-pill").text, "täglich · 22:00"
  end

  test "an Einzelschaltung that switches on points the other way" do
    assert_equal "→ an", render_entry(single(action: "on")).css(".sw-dir").text
  end

  test "the buttons of a Zeitfenster address the group and say Zeitfenster" do
    rendered = render_entry(window)

    assert rendered.css("form[action='/plugs/fridge/switch_windows/g-1/enabled']").any?
    assert rendered.css("a[href='/plugs/fridge/switch_windows/g-1/edit']").any?
    assert rendered.css("form[action='/plugs/fridge/switch_windows/g-1']").any?
    assert_equal [ "Zeitfenster pausieren", "Zeitfenster bearbeiten", "Zeitfenster löschen" ],
                 rendered.css("[aria-label]").map { |el| el["aria-label"] }
  end

  test "the buttons of an Einzelschaltung address the rule and say Schaltzeit" do
    rendered = render_entry(single)

    assert rendered.css("form[action='/plugs/fridge/switch_rules/7/enabled']").any?
    assert rendered.css("a[href='/plugs/fridge/switch_rules/7/edit']").any?
    assert rendered.css("form[action='/plugs/fridge/switch_rules/7']").any?
    assert_equal [ "Schaltzeit pausieren", "Schaltzeit bearbeiten", "Schaltzeit löschen" ],
                 rendered.css("[aria-label]").map { |el| el["aria-label"] }
  end

  test "a paused row is struck through and its button resumes instead" do
    rendered = render_entry(window(enabled: false))

    assert rendered.css("span.sw-pill.paused").any?
    assert_equal "Zeitfenster aktivieren", rendered.css("button[aria-label]").first["aria-label"]
    assert rendered.css("form[action$='/enabled'] input[name=enabled][value=true]").any?
  end

  test "a running row offers to pause" do
    rendered = render_entry(single)

    assert rendered.css("span.sw-pill.paused").none?
    assert rendered.css("form[action$='/enabled'] input[name=enabled][value=false]").any?
  end
end
