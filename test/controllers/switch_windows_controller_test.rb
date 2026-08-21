require "test_helper"

class SwitchWindowsControllerTest < ActionDispatch::IntegrationTest
  setup { Switching::Rule.delete_all }

  def valid_params
    { switch_window: { on_at_time: "18:00", off_at_time: "23:00", days: [ "", "1", "2" ] } }
  end

  def a_window(on: "18:00", off: "23:00", days: [ 1, 2, 3, 4, 5 ])
    Switching::Rules::SaveWindow.call(plug_id: "fridge", attrs: { on_at_time: on, off_at_time: off, days: days })
  end

  def rules_of(group_id) = Switching::Rule.where(group_id: group_id).order(:action)

  test "new renders the inline editor" do
    get "/plugs/fridge/switch_windows/new", as: :turbo_stream
    assert_response :success
    assert_match "sw_editor_fridge", @response.body
    assert_match "switch_window[days][]", @response.body
  end

  test "create writes both halves as one group and re-renders the rules region" do
    post "/plugs/fridge/switch_windows", params: valid_params, as: :turbo_stream
    assert_response :success

    off, on = Switching::Rule.order(:action).to_a
    assert_equal [ "fridge", 1080, [ 1, 2 ] ], [ on.plug_id, on.at_minute, on.days ]
    assert_equal [ "fridge", 1380, [ 1, 2 ] ], [ off.plug_id, off.at_minute, off.days ]
    assert_equal on.group_id, off.group_id
    assert_match "sw_rules_fridge", @response.body
    assert_match "sw_head_fridge", @response.body
  end

  test "create with no days re-renders the form with errors and 422" do
    post "/plugs/fridge/switch_windows",
         params: { switch_window: { on_at_time: "18:00", off_at_time: "23:00", days: [ "" ] } },
         as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal 0, Switching::Rule.count
    assert_match "Wochentag", @response.body
    assert_match "sw_editor_fridge", @response.body
  end

  test "create with two identical times is rejected" do
    post "/plugs/fridge/switch_windows",
         params: { switch_window: { on_at_time: "18:00", off_at_time: "18:00", days: [ "1" ] } },
         as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal 0, Switching::Rule.count
    assert_match "unterscheiden", @response.body
  end

  test "create for unknown plug returns 404, for non-switchable 422" do
    post "/plugs/nope/switch_windows", params: valid_params, as: :turbo_stream
    assert_response :not_found
    post "/plugs/bkw/switch_windows", params: valid_params, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "edit renders the form into the row of the group" do
    group_id = a_window
    get "/plugs/fridge/switch_windows/#{group_id}/edit", as: :turbo_stream
    assert_response :success
    assert_match "sw_entry_fridge_#{group_id}", @response.body
    assert_match "18:00", @response.body
    assert_match "23:00", @response.body
  end

  test "edit shows a window past midnight with the times and days that were typed" do
    group_id = a_window(on: "22:00", off: "06:00", days: [ 1, 2, 3, 4, 5 ])
    assert_equal [ 2, 3, 4, 5, 6 ], rules_of(group_id).find_by(action: "off").days

    get "/plugs/fridge/switch_windows/#{group_id}/edit", as: :turbo_stream
    assert_match "22:00", @response.body
    assert_match "06:00", @response.body
    # The off rule's shifted Saturday must not reach the form.
    assert_no_match(/switch_window\[days\]\[\]" value="6" checked/, @response.body)
  end

  test "update moves both halves in place, keeping the rule ids" do
    group_id = a_window
    before   = rules_of(group_id).pluck(:id)

    patch "/plugs/fridge/switch_windows/#{group_id}",
          params: { switch_window: { on_at_time: "09:00", off_at_time: "17:00", days: [ "", "6" ] } },
          as: :turbo_stream
    assert_response :success

    assert_equal before, rules_of(group_id).pluck(:id)
    assert_equal [ 1020, 540 ], rules_of(group_id).pluck(:at_minute)
    assert_equal [ [ 6 ], [ 6 ] ], rules_of(group_id).pluck(:days)
    assert_match "sw_rules_fridge", @response.body
  end

  test "failed update re-renders the form into the same row and 422" do
    group_id = a_window

    patch "/plugs/fridge/switch_windows/#{group_id}",
          params: { switch_window: { on_at_time: "", off_at_time: "23:00", days: [ "1" ] } },
          as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "sw_entry_fridge_#{group_id}", @response.body
    assert_equal [ 1080, 1380 ], Switching::Rule.where(group_id: group_id).order(:at_minute).pluck(:at_minute)
  end

  test "the member route pauses and resumes both halves at once" do
    group_id = a_window

    patch "/plugs/fridge/switch_windows/#{group_id}/enabled",
          params: { enabled: "false" }, as: :turbo_stream
    assert_response :success
    assert_equal [ false, false ], rules_of(group_id).pluck(:enabled)

    patch "/plugs/fridge/switch_windows/#{group_id}/enabled",
          params: { enabled: "true" }, as: :turbo_stream
    assert_equal [ true, true ], rules_of(group_id).pluck(:enabled)
  end

  test "destroy removes both halves" do
    group_id = a_window
    delete "/plugs/fridge/switch_windows/#{group_id}", as: :turbo_stream
    assert_response :success
    assert_equal 0, Switching::Rule.count
    assert_match "sw_rules_fridge", @response.body
  end

  test "a group that is not on this plug is not found" do
    group_id = a_window
    Switching::Rule.update_all(plug_id: "gone")

    get "/plugs/fridge/switch_windows/#{group_id}/edit", as: :turbo_stream
    assert_response :not_found
    patch "/plugs/fridge/switch_windows/#{group_id}", params: valid_params, as: :turbo_stream
    assert_response :not_found
    patch "/plugs/fridge/switch_windows/#{group_id}/enabled", params: { enabled: "false" }, as: :turbo_stream
    assert_response :not_found
    delete "/plugs/fridge/switch_windows/#{group_id}", as: :turbo_stream
    assert_response :not_found
  end

  test "a group missing its off half is not editable as a window" do
    group_id = a_window
    Switching::Rule.find_by(action: "off").destroy!

    get "/plugs/fridge/switch_windows/#{group_id}/edit", as: :turbo_stream
    assert_response :not_found
  end
end
