require "test_helper"

class PlugRosterTest < ActiveSupport::TestCase
  cover "Plugs::Roster*"

  def plug(id, role) = ConfigLoader::PlugCfg.new(id: id, name: id.upcase, role: role, driver: :shelly)

  def roster
    @roster ||= Plugs::Roster.new([ plug("bkw", :producer), plug("fridge", :consumer), plug("tv", :consumer) ])
  end

  test "selects by role, as objects and as ids" do
    assert_equal [ "bkw" ], roster.producers.map(&:id)
    assert_equal [ "fridge", "tv" ], roster.consumer_ids
    assert_equal [ "bkw" ], roster.producer_ids
    assert_equal [ "bkw", "fridge", "tv" ], roster.ids
  end

  test "role and plug lookup return nil for an unknown plug" do
    assert_equal :consumer, roster.role_of("fridge")
    assert_nil roster.role_of("nope")
    assert_nil roster.find("nope")
    assert_equal "FRIDGE", roster.find("fridge").name
  end

  test "producer watts are flipped positive, consumer watts stay as measured" do
    assert_equal 800.0, roster.signed_watts("bkw", -800.0)
    assert_equal 800.0, roster.signed_watts("bkw", 800.0)
    assert_equal(-50.0, roster.signed_watts("fridge", -50.0))
    assert_equal 50.0, roster.signed_watts("tv", 50.0)
  end

  test "buckets by role" do
    assert_equal :production_w, roster.bucket_key("bkw")
    assert_equal :consumption_w, roster.bucket_key("tv")
    assert roster.measured?("bkw")
  end

  test "a plug with an unknown role is not measured" do
    unknown = Plugs::Roster.new([ plug("mystery", :whatever) ])

    assert_not unknown.measured?("mystery")
    assert_not unknown.measured?("absent")
    assert_raises(KeyError) { unknown.bucket_key("mystery") }
  end

  test "wrap passes a roster through and wraps an array" do
    assert_same roster, Plugs::Roster.wrap(roster)
    assert_equal [ "bkw" ], Plugs::Roster.wrap([ plug("bkw", :producer) ]).ids
  end

  test "wrap passes a subclass instance through unchanged, without touching it" do
    sub_roster = Class.new(Plugs::Roster).new([ plug("bkw", :producer) ])

    assert_same sub_roster, Plugs::Roster.wrap(sub_roster)
  end

  test "empty roster" do
    empty = Plugs::Roster.new([])

    assert_empty empty.consumer_ids
    assert_empty empty.producers
  end

  test "normalizes any enumerable of plugs to an array" do
    normalized = Plugs::Roster.new([ plug("bkw", :producer) ].each).all

    assert_kind_of Array, normalized
    assert_equal [ "bkw" ], normalized.map(&:id)
  end

  test "memoized collections are frozen against accidental mutation" do
    assert roster.all.frozen?
    assert roster.ids.frozen?
    assert roster.consumer_ids.frozen?
    assert roster.producer_ids.frozen?
  end
end
