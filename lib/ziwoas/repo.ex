defmodule Ziwoas.Repo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :ziwoas,
    adapter: Ecto.Adapters.SQLite3
end
