defmodule Ziwoas.ApplicationTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Live.{DashboardWatcher, SensorsWatcher, SolakonWatcher}
  alias Ziwoas.Ownership

  @rails Ownership.all_rails()

  test "every bridge polls Rails' writes while Rails owns the tasks, in shadow too" do
    expected = [SensorsWatcher, {DashboardWatcher, live: true}, SolakonWatcher]

    assert Ziwoas.Application.watchers(@rails) == expected

    shadow = %{@rails | sensor_poll: :shadow, plug_ingest: :shadow, solakon_monitor: :shadow}
    assert Ziwoas.Application.watchers(shadow) == expected
  end

  test "the sensors bridge stands down once Phoenix polls the sensors itself" do
    assert Ziwoas.Application.watchers(%{@rails | sensor_poll: :phoenix}) == [
             {DashboardWatcher, live: true},
             SolakonWatcher
           ]
  end

  test "the collector's tasks broadcast themselves: Solakon beat and dashboard deltas" do
    owners = %{
      @rails
      | plug_ingest: :phoenix,
        solakon_monitor: :phoenix,
        solakon_control: :phoenix
    }

    assert Ziwoas.Application.watchers(owners) == [
             SensorsWatcher,
             {DashboardWatcher, live: false}
           ]
  end
end
