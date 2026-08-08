require "test_helper"

class SwitchRulesControllerTest < ActionDispatch::IntegrationTest
  setup { SwitchRule.delete_all }

  def valid_params
    { switch_rule: { at_minute_time: "22:00", action: "off", days: [ "", "1", "2" ] } }
  end

  def a_single(at: "22:00", action: "off", days: [ 1 ])
    SwitchRules::SaveSingle.call(plug_id: "fridge", attrs: { at_minute_time: at, action: action, days: days })
  end

  test "new renders the inline editor" do
    get "/plugs/fridge/switch_rules/new", as: :turbo_stream
    assert_response :success
    assert_match "sw_editor_fridge", @response.body
    assert_match "switch_rule[days][]", @response.body
  end

  test "create writes one rule without a group and re-renders the rules region" do
    post "/plugs/fridge/switch_rules", params: valid_params, as: :turbo_stream
    assert_response :success

    rule = SwitchRule.sole
    assert_equal [ "fridge", "off", 1320, [ 1, 2 ], true ],
                 [ rule.plug_id, rule.action, rule.at_minute, rule.days, rule.enabled ]
    assert_nil rule.group_id
    assert_match "sw_rules_fridge", @response.body
    assert_match "sw_head_fridge", @response.body
  end

  test "create rejects a direction that is neither on nor off" do
    post "/plugs/fridge/switch_rules",
         params: { switch_rule: { at_minute_time: "22:00", action: "toggle", days: [ "1" ] } },
         as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal 0, SwitchRule.count
    assert_match "Richtung", @response.body
  end

  test "create with no days re-renders the form with errors and 422" do
    post "/plugs/fridge/switch_rules",
         params: { switch_rule: { at_minute_time: "22:00", action: "off", days: [ "" ] } },
         as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal 0, SwitchRule.count
    assert_match "Wochentag", @response.body
  end

  test "create for unknown plug returns 404, for non-switchable 422" do
    post "/plugs/nope/switch_rules", params: valid_params, as: :turbo_stream
    assert_response :not_found
    post "/plugs/bkw/switch_rules", params: valid_params, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "edit renders the form into the row of the rule" do
    rule = a_single
    get "/plugs/fridge/switch_rules/#{rule.id}/edit", as: :turbo_stream
    assert_response :success
    assert_match "sw_entry_fridge_#{rule.id}", @response.body
    assert_match "22:00", @response.body
  end

  test "update changes the rule in place, keeping its id" do
    rule = a_single

    patch "/plugs/fridge/switch_rules/#{rule.id}",
          params: { switch_rule: { at_minute_time: "07:30", action: "on", days: [ "", "6", "7" ] } },
          as: :turbo_stream
    assert_response :success

    rule.reload
    assert_equal [ "on", 450, [ 6, 7 ] ], [ rule.action, rule.at_minute, rule.days ]
    assert_equal 1, SwitchRule.count
    assert_match "sw_rules_fridge", @response.body
  end

  test "update leaves a paused rule paused" do
    rule = a_single
    rule.update!(enabled: false)

    patch "/plugs/fridge/switch_rules/#{rule.id}",
          params: { switch_rule: { at_minute_time: "07:30", action: "on", days: [ "1" ] } },
          as: :turbo_stream
    assert_response :success
    refute rule.reload.enabled
  end

  test "failed update re-renders the form into the same row and 422" do
    rule = a_single

    patch "/plugs/fridge/switch_rules/#{rule.id}",
          params: { switch_rule: { at_minute_time: "99:99", action: "off", days: [ "1" ] } },
          as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "sw_entry_fridge_#{rule.id}", @response.body
    assert_equal 1320, rule.reload.at_minute
  end

  test "the member route pauses and resumes the rule" do
    rule = a_single

    patch "/plugs/fridge/switch_rules/#{rule.id}/enabled", params: { enabled: "false" }, as: :turbo_stream
    assert_response :success
    refute rule.reload.enabled

    patch "/plugs/fridge/switch_rules/#{rule.id}/enabled", params: { enabled: "true" }, as: :turbo_stream
    assert rule.reload.enabled
  end

  test "destroy removes the rule" do
    rule = a_single
    delete "/plugs/fridge/switch_rules/#{rule.id}", as: :turbo_stream
    assert_response :success
    assert_equal 0, SwitchRule.count
    assert_match "sw_rules_fridge", @response.body
  end

  test "a rule that is not on this plug is not found" do
    rule = a_single
    rule.update_column(:plug_id, "gone")

    get "/plugs/fridge/switch_rules/#{rule.id}/edit", as: :turbo_stream
    assert_response :not_found
    patch "/plugs/fridge/switch_rules/#{rule.id}", params: valid_params, as: :turbo_stream
    assert_response :not_found
    patch "/plugs/fridge/switch_rules/#{rule.id}/enabled", params: { enabled: "false" }, as: :turbo_stream
    assert_response :not_found
    delete "/plugs/fridge/switch_rules/#{rule.id}", as: :turbo_stream
    assert_response :not_found
  end

  test "the half of a group left over is editable as an Einzelschaltung" do
    group_id = SwitchRules::SaveWindow.call(
      plug_id: "fridge", attrs: { on_at_time: "10:00", off_at_time: "20:00", days: [ 1 ] }
    )
    SwitchRule.find_by(group_id: group_id, action: "on").destroy!
    orphan = SwitchRule.sole

    get "/plugs/fridge/switch_rules/#{orphan.id}/edit", as: :turbo_stream
    assert_response :success

    delete "/plugs/fridge/switch_rules/#{orphan.id}", as: :turbo_stream
    assert_response :success
    assert_equal 0, SwitchRule.count
  end
end
