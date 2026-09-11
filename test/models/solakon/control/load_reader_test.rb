require "test_helper"

class ControlLoadReaderTest < ActiveSupport::TestCase
  cover "Solakon::Control::LoadReader*"

  Plug = Struct.new(:id, :role, keyword_init: true)

  def roster(plugs = all_plugs) = Plugs::Roster.new(plugs)

  def all_plugs
    [ Plug.new(id: "bkw",    role: :producer),
      Plug.new(id: "fridge", role: :consumer),
      Plug.new(id: "tv",     role: :consumer) ]
  end

  setup do
    Plugs::Sample.delete_all
    @original_time_zone = Time.zone
    Time.zone = "Europe/Berlin"
  end

  teardown { Time.zone = @original_time_zone }

  test "current_consumption_w sums latest fresh consumer samples, ignores producer" do
    now = Time.at(1_000_000)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 10, apower_w: 100, aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 5,  apower_w: 120, aenergy_wh: 1) # latest wins
    Plugs::Sample.create!(plug_id: "tv",     ts: now.to_i - 5,  apower_w: 30,  aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "bkw",    ts: now.to_i - 5,  apower_w: 500, aenergy_wh: 1) # producer, ignored
    reader = Solakon::Control::LoadReader.new(roster: roster, now: now, offline_after_s: 120)
    assert_in_delta 150.0, reader.current_consumption_w
  end

  test "guaranteed_floor_w is the minimum 5-min total over 24h" do
    now = Time.at(1_000_000)
    # bucket A (low total = 100): -1000s
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 1000, apower_w: 100, aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "tv",     ts: now.to_i - 1000, apower_w: 0,   aenergy_wh: 1)
    # bucket B (high total = 300, 15 min later): -100s
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 100,  apower_w: 200, aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "tv",     ts: now.to_i - 100,  apower_w: 100, aenergy_wh: 1)
    reader = Solakon::Control::LoadReader.new(roster: roster, now: now)
    assert_in_delta 100.0, reader.guaranteed_floor_w
  end

  test "guaranteed_floor_w ignores samples older than 24h" do
    now = Time.at(1_000_000)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 100,    apower_w: 250, aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 90_000, apower_w: 10,  aenergy_wh: 1) # >24h
    reader = Solakon::Control::LoadReader.new(roster: roster, now: now)
    assert_in_delta 250.0, reader.guaranteed_floor_w
  end

  test "load_estimate memoizes the floor but reads live consumption fresh" do
    now = Time.at(1_000_000)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 120, aenergy_wh: 1)
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write(Solakon::Control::LoadReader::FLOOR_CACHE_KEY, 85.0)

    estimate = Solakon::Control::LoadReader.new(roster: roster, now: now, offline_after_s: 120,
                                                cache: cache).load_estimate

    assert_in_delta 120.0, estimate.current_w
    assert_in_delta 85.0, estimate.floor_w
  end

  test "load_estimate computes and stores the floor on a cold cache" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 120, aenergy_wh: 1)
    cache = ActiveSupport::Cache::MemoryStore.new

    estimate = Solakon::Control::LoadReader.new(roster: roster, now: now, offline_after_s: 120,
                                                cache: cache).load_estimate

    assert_in_delta 120.0, estimate.floor_w
    assert_in_delta 120.0, cache.read(Solakon::Control::LoadReader::FLOOR_CACHE_KEY)
  end

  test "load_estimate refreshes the cached floor after one hour" do
    cache = ActiveSupport::Cache::MemoryStore.new
    start = Time.zone.local(2026, 6, 20, 12, 0, 0)

    travel_to(start) do
      reader = Solakon::Control::LoadReader.new(roster: roster([]), now: start, cache: cache)
      reader.stub(:guaranteed_floor_w, 120.0) do
        assert_equal 120.0, reader.load_estimate.floor_w
      end
    end

    later = start + Solakon::Control::LoadReader::FLOOR_CACHE_TTL + 1.second
    travel_to(later) do
      reader = Solakon::Control::LoadReader.new(roster: roster([]), now: later, cache: cache)
      reader.stub(:guaranteed_floor_w, 50.0) do
        assert_equal 50.0, reader.load_estimate.floor_w
      end
    end
  end

  test "no consumer plugs: consumption is nil, floor is zero" do
    reader = Solakon::Control::LoadReader.new(roster: roster([]), now: Time.at(1_000_000))
    assert_nil reader.current_consumption_w
    assert_equal 0.0, reader.guaranteed_floor_w
  end

  test "now and offline_after_s default sensibly when omitted" do
    Plugs::Sample.create!(plug_id: "fridge", ts: Time.now.to_i - 5, apower_w: 120, aenergy_wh: 1)

    reader = Solakon::Control::LoadReader.new(roster: roster)

    assert_in_delta 120.0, reader.current_consumption_w
  end

  test "cache defaults to Rails.cache when none is supplied" do
    now = Time.at(1_000_000)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 120, aenergy_wh: 1)

    reader = Solakon::Control::LoadReader.new(roster: roster, now: now, offline_after_s: 120)

    assert_in_delta 120.0, reader.load_estimate.current_w
  end

  test "guaranteed_floor_w only sums consumer plugs, never the roster's producer" do
    now = Time.at(1_000_000)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 100, apower_w: 100, aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "tv",     ts: now.to_i - 100, apower_w: 50,  aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "bkw",    ts: now.to_i - 100, apower_w: 900, aenergy_wh: 1)
    reader = Solakon::Control::LoadReader.new(roster: roster, now: now)

    assert_in_delta 150.0, reader.guaranteed_floor_w
  end

  test "guaranteed_floor_w includes a sample taken at the exact current second" do
    now = Time.at(1_000_000)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i, apower_w: 300, aenergy_wh: 1)
    reader = Solakon::Control::LoadReader.new(roster: roster, now: now)

    assert_in_delta 300.0, reader.guaranteed_floor_w
  end

  test "guaranteed_floor_w excludes a sample from one second after the current time" do
    now = Time.at(1_000_000)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 100, apower_w: 300, aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i + 1,   apower_w: 0,   aenergy_wh: 1)
    reader = Solakon::Control::LoadReader.new(roster: roster, now: now)

    assert_in_delta 300.0, reader.guaranteed_floor_w
  end

  test "guaranteed_floor_w takes the minimum bucket, not merely the first one" do
    now = Time.at(1_000_000)
    # earlier bucket (high total): -1000s
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 1000, apower_w: 300, aenergy_wh: 1)
    # later bucket (low total): -100s
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 100, apower_w: 50, aenergy_wh: 1)
    reader = Solakon::Control::LoadReader.new(roster: roster, now: now)

    assert_in_delta 50.0, reader.guaranteed_floor_w
  end

  test "current_consumption_w honors a custom staleness window, not Measurement's own default" do
    now = Time.at(1_000_000)
    Plugs::Sample.create!(plug_id: "fridge", ts: now.to_i - 50, apower_w: 200, aenergy_wh: 1)
    reader = Solakon::Control::LoadReader.new(roster: roster, now: now, offline_after_s: 10)

    assert_nil reader.current_consumption_w
  end
end
