defmodule Ziwoas.Repo.Migrations.AddRoomAirToSensorReadings do
  @moduledoc """
  The SEN66's quantities. `humidity` stays an INTEGER column: SQLite keeps a value like
  48.2 as REAL there all the same, so only the Ecto schema turns it into a float.
  """
  use Ecto.Migration

  def change do
    alter table(:sensor_readings) do
      add :pm1_0, :real
      add :pm2_5, :real
      add :pm4_0, :real
      add :pm10, :real
      add :voc_index, :integer
      add :nox_index, :integer
      add :device_status, :integer
    end
  end
end
