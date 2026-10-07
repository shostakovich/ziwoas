defmodule Ziwoas.Trmnl.Push do
  @moduledoc """
  Pushes a widget's `merge_variables` to its TRMNL webhook (Rails'
  `TrmnlPushJob` and `TrmnlSensorPushJob`): ActiveSupport's JSON bytes, at most
  2 kB, one POST without retry. Logs what Rails logs; a failed POST is a warning,
  an oversized payload raises `PayloadTooLarge`.

  Only the task's owner posts (`Ownership.ensure_owner!/1` right before it); in
  `dry_run` or `shadow` the payload is built and checked, then only logged.
  """
  require Logger

  alias Ziwoas.{Http, Ownership, RubyJSON}

  @max_payload_bytes 2048
  @timeout_ms 10_000

  defmodule PayloadTooLarge do
    @moduledoc "The payload exceeds what a TRMNL webhook accepts."
    defexception [:message]
  end

  @type widget :: :energy | :sensors

  @doc """
  Builds the payload with `build` (only when a webhook URL is configured) and
  pushes it for `task`. Returns `:skipped` without a URL, `:logged` when not the
  owner, else `:ok` or `:failed`.
  """
  @spec run(Ownership.task(), widget, String.t() | nil, (-> term)) ::
          :ok | :failed | :skipped | :logged
  def run(task, widget, url, build) do
    if url in [nil, ""] do
      Logger.info("#{push(widget)} skipped (no webhook URL configured)")
      :skipped
    else
      body = RubyJSON.encode!(build.())
      bytes = byte_size(body)

      if bytes > @max_payload_bytes do
        raise PayloadTooLarge,
              "#{payload(widget)} is #{bytes} B, exceeds #{@max_payload_bytes} B limit"
      end

      if Ownership.may_write_devices?(task) do
        post(task, widget, url, body)
      else
        Logger.info("#{push(widget)} (#{Ownership.mode(task)}): #{bytes} B, not sent")
        :logged
      end
    end
  end

  defp post(task, widget, url, body) do
    Ownership.ensure_owner!(task)

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
