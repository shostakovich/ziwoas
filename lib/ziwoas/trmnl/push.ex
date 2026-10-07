defmodule Ziwoas.Trmnl.Push do
  @moduledoc """
  Pushes a widget's `merge_variables` to its TRMNL webhook: JSON of at most
  2 kB, one POST without retry. A failed POST is a warning, an oversized
  payload raises `PayloadTooLarge`.
  """
  require Logger

  alias Ziwoas.Http

  @max_payload_bytes 2048
  @timeout_ms 10_000

  defmodule PayloadTooLarge do
    @moduledoc "The payload exceeds what a TRMNL webhook accepts."
    defexception [:message]
  end

  @type widget :: :energy | :sensors

  def max_payload_bytes, do: @max_payload_bytes

  @doc """
  Builds the payload with `build` (only when a webhook URL is configured) and
  POSTs it. Returns `:skipped` without a URL, else `:ok` or `:failed`. The
  first argument is ignored (it named the scheduler task).
  """
  @spec run(widget, String.t() | nil, (-> term)) :: :ok | :failed | :skipped
  def run(widget, url, build) do
    if url in [nil, ""] do
      Logger.info("#{push(widget)} skipped (no webhook URL configured)")
      :skipped
    else
      body = JSON.encode!(build.())
      bytes = byte_size(body)

      if bytes > @max_payload_bytes do
        raise PayloadTooLarge,
              "#{payload(widget)} is #{bytes} B, exceeds #{@max_payload_bytes} B limit"
      end

      post(widget, url, body)
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
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("#{push(widget)} failed: HTTP #{status} #{reason_phrase(status)}")
        :failed

      {:error, exception} ->
        Logger.warning(
          "#{push(widget)} errored: #{inspect(exception.__struct__)}: #{Exception.message(exception)}"
        )

        :failed
    end
  end

  defp push(:energy), do: "TRMNL push"
  defp push(:sensors), do: "TRMNL sensor push"

  defp payload(:energy), do: "TRMNL payload"
  defp payload(:sensors), do: "TRMNL sensor payload"

  defp reason_phrase(status) do
    Plug.Conn.Status.reason_phrase(status)
  rescue
    ArgumentError -> ""
  end
end
