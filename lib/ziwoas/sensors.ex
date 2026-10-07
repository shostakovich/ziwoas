defmodule Ziwoas.Sensors do
  @moduledoc """
  The air sensors' readings (`sensor_readings`) and what they mean: the CO₂
  traffic light, a low battery, a sensor gone offline (no reading, or none for
  30 minutes).

  `subscribe/0` delivers `{:polled, instant}` after a poll stored its readings.
  """
  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Sensors.Reading

  @topic inspect(__MODULE__)

  @co2_warn_ppm 1000
  @co2_bad_ppm 1400
  @battery_low_pct 20
  @offline_after_s 30 * 60
  @outdoor_freshness_s 30 * 60

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @doc "Tells the subscribers that the poll at `instant` is stored."
  @spec notify_polled(DateTime.t()) :: :ok
  def notify_polled(%DateTime{} = instant) do
    broadcast(:polled, instant)
    :ok
  end

  defp broadcast(event, payload),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {event, payload})

  # --- Storing --------------------------------------------------------------------

  @doc """
  Stores a reading of `device_id` at `taken_at` from a sensor's measurements
  (`Ziwoas.Sensors.SwitchBotClient.status()`); whole numbers given as floats are rounded.
  """
  @spec create_reading(String.t(), DateTime.t(), map) ::
          {:ok, Reading.t()} | {:error, Ecto.Changeset.t()}
  def create_reading(device_id, %DateTime{} = taken_at, measurements),
    do: device_id |> Reading.changeset(taken_at, measurements) |> Repo.insert()

  # --- Reading --------------------------------------------------------------------

  @doc "The newest reading of a device, or nil."
  @spec latest(String.t()) :: Reading.t() | nil
  def latest(device_id) do
    Repo.one(
      from r in Reading,
        where: r.device_id == ^device_id,
        order_by: [desc: r.taken_at, desc: r.id],
        limit: 1
    )
  end

  @doc """
  Each device's newest reading, keyed by device: of readings sharing the newest
  `taken_at`, the last one stored wins.
  """
  @spec latest_per_device([String.t()]) :: %{String.t() => Reading.t()}
  def latest_per_device([]), do: %{}

  def latest_per_device(device_ids) do
    newest =
      from r in Reading,
        where: r.device_id in ^device_ids,
        group_by: r.device_id,
        select: %{device_id: r.device_id, taken_at: max(r.taken_at)}

    from(r in Reading,
      join: n in subquery(newest),
      on: n.device_id == r.device_id and n.taken_at == r.taken_at,
      order_by: r.id
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

  @doc "When a device last reported, or nil."
  @spec latest_taken_at(String.t()) :: DateTime.t() | nil
  def latest_taken_at(device_id) do
    Repo.one(from r in Reading, where: r.device_id == ^device_id, select: max(r.taken_at))
  end

  @doc "The newest outdoor reading from the last 30 minutes, or nil."
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

  @doc "`{taken_at, value}` of `column` in `[from, to)`, oldest first."
  @spec values_between(String.t(), :temperature | :co2, DateTime.t(), DateTime.t()) ::
          [{DateTime.t(), number | nil}]
  def values_between(device_id, column, from, to) do
    Repo.all(
      from r in Reading,
        where: r.device_id == ^device_id and r.taken_at >= ^from and r.taken_at < ^to,
        order_by: r.taken_at,
        select: {r.taken_at, field(r, ^column)}
    )
  end

  # --- Meaning --------------------------------------------------------------------

  @doc "From here on CO₂ is `:warn` (ppm)."
  @spec co2_warn_ppm() :: pos_integer
  def co2_warn_ppm, do: @co2_warn_ppm

  @doc "Above this CO₂ is `:bad` (ppm)."
  @spec co2_bad_ppm() :: pos_integer
  def co2_bad_ppm, do: @co2_bad_ppm

  @doc "The CO₂ traffic light of a reading or a ppm value; nil without CO₂."
  @spec co2_level(Reading.t() | integer | nil) :: :good | :warn | :bad | nil
  def co2_level(%Reading{co2: ppm}), do: co2_level(ppm)
  def co2_level(ppm) when is_integer(ppm) and ppm > @co2_bad_ppm, do: :bad
  def co2_level(ppm) when is_integer(ppm) and ppm >= @co2_warn_ppm, do: :warn
  def co2_level(ppm) when is_integer(ppm), do: :good
  def co2_level(_reading), do: nil

  @spec battery_low?(Reading.t() | nil) :: boolean
  def battery_low?(%Reading{battery_pct: pct}) when is_integer(pct), do: pct <= @battery_low_pct
  def battery_low?(_reading), do: false

  @doc "Whole seconds since the reading was taken, truncated; nil without a reading."
  @spec age_s(Reading.t() | nil, DateTime.t()) :: integer | nil
  def age_s(nil, _now), do: nil
  def age_s(%Reading{} = reading, now), do: div(age_us(reading, now), 1_000_000)

  @spec offline?(Reading.t() | nil, DateTime.t()) :: boolean
  def offline?(nil, _now), do: true
  def offline?(%Reading{} = reading, now), do: age_us(reading, now) > @offline_after_s * 1_000_000

  defp age_us(%Reading{taken_at: taken_at}, now), do: DateTime.diff(now, taken_at, :microsecond)
end
