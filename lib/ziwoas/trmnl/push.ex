defmodule Ziwoas.Trmnl.Push do
  @moduledoc false
  require Logger

  alias Ziwoas.Http

  @max_payload_bytes 2048
  @timeout_ms 10_000

  @type widget :: :energy | :sensors
  @type reason :: {:payload_too_large, pos_integer} | {:http_status, pos_integer} | Exception.t()

  def max_payload_bytes, do: @max_payload_bytes

  @spec run(widget, String.t() | nil, (-> term)) :: {:ok, :sent | :skipped} | {:error, reason}
  def run(widget, url, build) do
    if url in [nil, ""] do
      Logger.info("#{push(widget)} skipped (no webhook URL configured)")
      {:ok, :skipped}
    else
      body = JSON.encode!(build.())

      case byte_size(body) do
        bytes when bytes > @max_payload_bytes ->
          Logger.error("#{payload(widget)} is #{bytes} B, exceeds #{@max_payload_bytes} B limit")

          {:error, {:payload_too_large, bytes}}

        _bytes ->
          post(widget, url, body)
      end
    end
  end

  defp post(widget, url, body) do
    request =
      Http.new(__MODULE__,
        url: url,
        body: body,
        headers: [{"content-type", "application/json"}],
        retry: false,
        connect_options: [timeout: @timeout_ms],
        receive_timeout: @timeout_ms
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        Logger.info("#{push(widget)}: HTTP #{status}, #{byte_size(body)} B")
        {:ok, :sent}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("#{push(widget)} failed: HTTP #{status}")
        {:error, {:http_status, status}}

      {:error, exception} ->
        Logger.warning(
          "#{push(widget)} errored: #{inspect(exception.__struct__)}: #{Exception.message(exception)}"
        )

        {:error, exception}
    end
  end

  defp push(:energy), do: "TRMNL push"
  defp push(:sensors), do: "TRMNL sensor push"

  defp payload(:energy), do: "TRMNL payload"
  defp payload(:sensors), do: "TRMNL sensor payload"
end
