defmodule Ziwoas.Trmnl.Push do
  @moduledoc """
  Pushes a widget's `merge_variables` to its TRMNL webhook: JSON of at most
  2 kB, one POST without retry. Every outcome is logged under the widget's name;
  a failure comes back as `{:error, reason}`: `{:payload_too_large, bytes}`,
  `{:http_status, status}` or Req's transport exception.
  """
  require Logger

  alias Plug.Conn.Status
  alias Ziwoas.Http

  @max_payload_bytes 2048
  @timeout_ms 10_000

  @type widget :: :energy | :sensors
  @type reason :: {:payload_too_large, pos_integer} | {:http_status, pos_integer} | Exception.t()

  def max_payload_bytes, do: @max_payload_bytes

  @doc """
  Builds the payload with `build` (only when a webhook URL is configured) and
  POSTs it: `{:ok, :skipped}` without a URL, `{:ok, :sent}` once TRMNL took it.
  """
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
        Logger.warning("#{push(widget)} failed: HTTP #{status} #{reason_phrase(status)}")
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

  # Plug knows only the registered codes and raises for the others.
  defp reason_phrase(status) do
    Status.reason_phrase(status)
  rescue
    ArgumentError -> ""
  end
end
