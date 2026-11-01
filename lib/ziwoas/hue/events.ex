defmodule Ziwoas.Hue.Events do
  @moduledoc "The bridge's event stream: server-sent events whose data is a JSON list of events."

  @doc "Splits off the complete events; the rest waits for the next chunk."
  @spec parse(String.t()) :: {[map], String.t()}
  def parse(buffer) do
    blocks = buffer |> String.replace("\r\n", "\n") |> String.split("\n\n")
    {complete, [rest]} = Enum.split(blocks, -1)
    {Enum.flat_map(complete, &events/1), rest}
  end

  defp events(block) do
    data =
      for "data:" <> line <- String.split(block, "\n"), into: "", do: String.trim_leading(line)

    case data != "" and JSON.decode(data) do
      {:ok, events} when is_list(events) -> Enum.filter(events, &is_map/1)
      _no_events -> []
    end
  end
end
