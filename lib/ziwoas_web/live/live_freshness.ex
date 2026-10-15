defmodule ZiwoasWeb.LiveFreshness do
  @moduledoc false
  use ZiwoasWeb, :html

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Ziwoas.{Clock, Config, Plugs, Solakon}
  alias Ziwoas.Plugs.{Measurement, Roster}
  alias Ziwoas.Solakon.Reading

  @check_ms 10_000

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: schedule_check()

    {:cont,
     socket
     |> assign(:live_at, newest_data_at(Clock.now()))
     |> assign_stale()
     |> attach_hook(:live_freshness, :handle_info, &handle_info/2)}
  end

  defp handle_info(:check_freshness, socket) do
    schedule_check()
    {:halt, assign_stale(socket)}
  end

  defp handle_info({:live, _deltas}, socket), do: {:cont, fresh(socket)}
  defp handle_info({:reading, %Reading{}}, socket), do: {:cont, fresh(socket)}
  defp handle_info(_message, socket), do: {:cont, socket}

  defp fresh(socket), do: assign(socket, live_at: Clock.now(), stale: false)

  defp assign_stale(socket) do
    stale = DateTime.diff(Clock.now(), socket.assigns.live_at) > Measurement.offline_after_s()
    assign(socket, :stale, stale)
  end

  defp newest_data_at(now) do
    plug_ids = Config.get() |> Config.plug_roster() |> Roster.ids()
    plug_ts = Plugs.latest_sample_ts(plug_ids, 0, DateTime.to_unix(now) + 1)
    reading = Solakon.latest_reading()

    [plug_ts && DateTime.from_unix!(plug_ts), reading && reading.taken_at]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> now end)
  end

  defp schedule_check, do: Process.send_after(self(), :check_freshness, @check_ms)

  attr :stale, :boolean, required: true
  attr :live_at, DateTime, required: true
  attr :zone, :string, required: true
  slot :inner_block, required: true

  def live_header(assigns) do
    ~H"""
    <.header>
      {render_slot(@inner_block)}
      <:badge :if={@stale}>
        <.badge id="live_stale" tone={:warning}>veraltet</.badge>
      </:badge>
      <:subtitle :if={@stale}>
        Keine neuen Messwerte seit {clock(@live_at, @zone)} Uhr
      </:subtitle>
    </.header>
    """
  end
end
