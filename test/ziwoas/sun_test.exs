defmodule Ziwoas.SunTest do
  use ExUnit.Case, async: true

  alias Ziwoas.{Location, Sun}

  test "a location without coordinates knows no sun and counts as day" do
    location = Location.new("Europe/Berlin")

    refute Sun.known?(location)
    assert Sun.position(location, ~U[2026-06-21 12:00:00Z]) == nil
    assert Sun.sunrise(location, ~D[2026-06-21]) == nil
    assert Sun.sunset(location, ~D[2026-06-21]) == nil
    assert Sun.path(location, ~D[2026-06-21]) == []
    assert Sun.daytime?(location, ~U[2026-06-21 23:00:00Z])
  end

  test "a location needs a valid IANA time zone" do
    assert_raise ArgumentError, ~r/not a valid IANA timezone/, fn ->
      Location.new("Mars/Olympus")
    end
  end
end
