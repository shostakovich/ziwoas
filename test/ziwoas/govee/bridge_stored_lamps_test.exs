defmodule Ziwoas.Govee.BridgeStoredLampsTest do
  use Ziwoas.DataCase

  alias Ziwoas.Config.Govee
  alias Ziwoas.Govee.{Bridge, DeviceRegistry}
  alias Ziwoas.Lights.Light
  alias Ziwoas.Repo

  @moduletag :shared_sandbox
  @moduletag :capture_log

  test "the bridge starts from the Govee lamps stored in the database" do
    Repo.insert!(%Light{key: "14ABDB4844064B60", name: "Uplighter"})
    Repo.insert!(%Light{key: "HUE1", name: "Hue", vendor: :hue})
    down = &Plug.Conn.send_resp(&1, 200, ~s({"code":500,"message":"down"}))

    bridge =
      start_supervised!(
        {Bridge,
         name: nil,
         govee: %Govee{
           api_key: "k",
           lan_poll_seconds: 3600,
           api_poll_seconds: 3600,
           pending_window_seconds: 5,
           names: %{}
         },
         api_req: [plug: down],
         tasks: start_supervised!(Task.Supervisor),
         send: fn _datagram -> :ok end,
         listen_port: false}
      )

    assert [%{key: "14ABDB4844064B60"}] = DeviceRegistry.all(:sys.get_state(bridge).registry)
  end
end
