require "test_helper"

class LatestPerPlugTest < ActiveSupport::TestCase
  setup { Sample.delete_all }

  class Undeclared < Sample
    self.latest_per_plug_column = nil
  end

  test "a model that never declared its column says so" do
    error = assert_raises(ArgumentError) { Undeclared.latest_per_plug([ "probe" ]) }
    assert_match "latest_per_plug_by", error.message
  end

  test "a subclass inherits the declared column" do
    now = Time.at(1_000_000)
    Sample.create!(plug_id: "probe", ts: now.to_i - 30, apower_w: 100.0, aenergy_wh: 1.0)
    Sample.create!(plug_id: "probe", ts: now.to_i - 5,  apower_w: 120.0, aenergy_wh: 1.0)

    subclass = Class.new(Sample)

    assert_in_delta 120.0, subclass.latest_per_plug([ "probe" ]).sole.apower_w
  end
end
