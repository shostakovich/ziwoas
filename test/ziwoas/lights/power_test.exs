defmodule Ziwoas.Lights.PowerTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Lights.{Light, Power}
  alias Ziwoas.Plugs.Plug

  @shelly %Plug{id: "lamp", name: "Lampe", role: :consumer, driver: :shelly, switchable: true}

  test "only a switchable Shelly plug powers a lamp" do
    assert Power.lamp_plug?(@shelly)
    refute Power.lamp_plug?(%{@shelly | switchable: false})
    refute Power.lamp_plug?(%{@shelly | driver: :fritz_dect})
  end

  test "a lamp's plug is its stored one, if that is a lamp plug" do
    light = %Light{key: "FL1", shelly_plug_id: "lamp"}
    fritz = %{@shelly | driver: :fritz_dect}

    assert Power.plug(light, [@shelly]) == @shelly
    assert Power.plug(light, [fritz]) == nil
    assert Power.plug(%{light | shelly_plug_id: nil}, [@shelly]) == nil
  end
end
