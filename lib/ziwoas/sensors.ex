defmodule Ziwoas.Sensors do
  @moduledoc "Queries over `sensor_readings` (Rails' `SensorReading` scopes)."
  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Sensors.Reading

  @outdoor_freshness_s 30 * 60

  @doc "The newest reading of a device, or nil."
  @spec latest(String.t()) :: Reading.t() | nil
  def latest(device_id) do
    Repo.one(
      from r in Reading,
        where: r.device_id == ^device_id,
        order_by: [desc: r.taken_at],
        limit: 1
    )
  end

  @doc """
  Each device's newest readings, keyed by device (`SensorReading.latest_per_device`
  plus `index_by`): readings sharing the newest `taken_at` leave the last one.
  """
  @spec latest_per_device([String.t()]) :: %{String.t() => Reading.t()}
  def latest_per_device([]), do: %{}

  def latest_per_device(device_ids) do
    from(r in Reading,
      where:
        r.device_id in ^device_ids and
          r.taken_at ==
            fragment(
              "(SELECT MAX(taken_at) FROM sensor_readings sr2 WHERE sr2.device_id = ?)",
              r.device_id
            )
    )
    |> Repo.all()
    |> Map.new(&{&1.device_id, &1})
  end

  @doc "The readings of `device_ids` from `since` on, oldest first."
  @spec since([String.t()], DateTime.t()) :: [Reading.t()]
  def since(device_ids, since) do
    Repo.all(
      from r in Reading,
        where: r.device_id in ^device_ids and r.taken_at >= ^since,
        order_by: r.taken_at
    )
  end

  @doc "The newest reading's id: changes whenever a reading arrives."
  @spec max_id() :: integer | nil
  def max_id, do: Repo.one(from r in Reading, select: max(r.id))

  @doc "When a device last reported, or nil."
  @spec latest_taken_at(String.t()) :: DateTime.t() | nil
  def latest_taken_at(device_id) do
    Repo.one(from r in Reading, where: r.device_id == ^device_id, select: max(r.taken_at))
  end

  @doc "The newest outdoor reading from the last 30 minutes, or nil (`SensorReading.fresh_outdoor`)."
  @spec fresh_outdoor([String.t()], DateTime.t()) :: Reading.t() | nil
  def fresh_outdoor([], _now), do: nil

  def fresh_outdoor(device_ids, now) do
    since = DateTime.add(now, -@outdoor_freshness_s, :second)

    Repo.one(
      from r in Reading,
        where: r.device_id in ^device_ids and r.taken_at >= ^since,
        order_by: [desc: r.taken_at],
        limit: 1
    )
  end

  @doc "`{taken_at, value}` of `column` in `[from, to)`, in SQLite's own row order."
  @spec values_between(String.t(), :temperature | :co2, DateTime.t(), DateTime.t()) ::
          [{DateTime.t(), number | nil}]
  def values_between(device_id, column, from, to) do
    Repo.all(
      from r in Reading,
        where: r.device_id == ^device_id and r.taken_at >= ^from and r.taken_at < ^to,
        select: {r.taken_at, field(r, ^column)}
    )
  end
end
