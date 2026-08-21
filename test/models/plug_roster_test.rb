require "test_helper"

class PlugRosterTest < ActiveSupport::TestCase
  def plug(id, role) = ConfigLoader::PlugCfg.new(id: id, name: id.upcase, role: role, driver: :shelly)

  def roster
    @roster ||= PlugRoster.new([ plug("bkw", :producer), plug("fridge", :consumer), plug("tv", :consumer) ])
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
    unknown = PlugRoster.new([ plug("mystery", :whatever) ])

    assert_not unknown.measured?("mystery")
    assert_not unknown.measured?("absent")
    assert_raises(KeyError) { unknown.bucket_key("mystery") }
  end

  test "wrap passes a roster through and wraps an array" do
    assert_same roster, PlugRoster.wrap(roster)
    assert_equal [ "bkw" ], PlugRoster.wrap([ plug("bkw", :producer) ]).ids
  end

  test "empty roster" do
    empty = PlugRoster.new([])

    assert_empty empty.consumer_ids
    assert_empty empty.producers
  end
end
