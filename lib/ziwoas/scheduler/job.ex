defmodule Ziwoas.Scheduler.Job do
  @moduledoc false

  @callback perform(opts :: keyword) :: any
end
