defmodule Ziwoas.Live do
  @moduledoc "Live updates for the pages: a PubSub message on a page's topic."

  @spec broadcast(String.t(), term) :: :ok | {:error, term}
  def broadcast(topic, message), do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, topic, message)
end
