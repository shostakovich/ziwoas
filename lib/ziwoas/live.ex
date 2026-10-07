defmodule Ziwoas.Live do
  @moduledoc """
  Live updates from the tasks Phoenix runs (Rails' `WeatherBroadcaster`,
  `SensorsBroadcaster`): a PubSub message on a page's topic, only as the task's
  owner. In shadow mode the pages still hear from Rails' writes
  (`Ziwoas.Live.*Watcher`), never from the shadow database.
  """
  alias Ziwoas.Ownership

  @spec broadcast(Ownership.task(), String.t(), term) :: :ok | :skipped | {:error, term}
  def broadcast(task, topic, message) do
    if Ownership.owner?(task),
      do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, topic, message),
      else: :skipped
  end
end
