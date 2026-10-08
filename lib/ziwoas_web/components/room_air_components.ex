defmodule ZiwoasWeb.RoomAirComponents do
  @moduledoc """
  A room's air on `/sensors` and the dashboard (CONTEXT.md, "Room air"): its room reading with
  each value's source, the air verdict, the ventilation hint and the sensors behind them.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.SensorsComponents, only: [co2_gauge: 1, age_label: 2]

  alias Ziwoas.Config.Sensor
  alias Ziwoas.Sensors
  alias Ziwoas.Sensors.{Reading, RoomReading}

  @labels %{
    co2: "CO₂",
    pm1_0: "PM1",
    pm2_5: "PM2,5",
    pm4_0: "PM4",
    pm10: "PM10",
    voc_index: "VOC",
    nox_index: "NOx",
    temperature: "Temperatur",
    humidity: "Luftfeuchte"
  }
  # Words for groups of quantities in sentences; PM sizes are one "Feinstaub".
  @groups %{
    co2: "CO₂",
    pm1_0: "Feinstaub",
    pm2_5: "Feinstaub",
    pm4_0: "Feinstaub",
    pm10: "Feinstaub",
    voc_index: "VOC",
    nox_index: "NOx",
    temperature: "Temperatur",
    humidity: "Feuchte"
  }
  @units %{
    co2: "ppm",
    pm1_0: "µg/m³",
    pm2_5: "µg/m³",
    pm4_0: "µg/m³",
    pm10: "µg/m³",
    temperature: "°C",
    humidity: "%"
  }
  @precision %{pm1_0: 1, pm2_5: 1, pm4_0: 1, pm10: 1, temperature: 1}
  @verdict_quantities [:co2, :pm2_5, :pm10, :voc_index, :nox_index]
  @tile_quantities [:pm2_5, :pm10, :voc_index, :nox_index, :temperature, :humidity]
  @start_up_quantities [:voc_index, :nox_index]
  @voc_meaning "100 = Mittel der letzten 24 h"
  @level_badges %{good: "text-bg-success", warn: "text-bg-warning", bad: "text-bg-danger"}
  @level_texts %{
    good: "text-success-emphasis",
    warn: "text-warning-emphasis",
    bad: "text-danger-emphasis"
  }
  @level_tints %{warn: "bg-warning-subtle", bad: "bg-danger-subtle"}
  @device_status %{
    fan_speed_warning: {"Lüfterdrehzahl weicht ab", "Feinstaubwerte können ungenau sein"},
    fan_error: {"Lüfter ausgefallen", "Feinstaubwerte fehlen oder sind falsch"},
    rht_error: {"Temperatur- und Feuchtesensor gestört", "Temperatur und Feuchte sind unsicher"},
    gas_error: {"VOC/NOx-Sensor gestört", "VOC und NOx sind unsicher"},
    co2_1_error: {"CO₂-Sensor gestört", "CO₂ ist unsicher"},
    co2_2_error: {"CO₂-Sensor gestört", "CO₂ ist unsicher"},
    hcho_error: {"Formaldehydsensor gestört", nil},
    pm_error: {"Feinstaubsensor gestört", "Feinstaubwerte sind unsicher"}
  }
  @pm_bins [
    {"bis 1 µm", nil, :pm1_0},
    {"1–2,5 µm", :pm1_0, :pm2_5},
    {"2,5–4 µm", :pm2_5, :pm4_0},
    {"4–10 µm", :pm4_0, :pm10}
  ]

  @typedoc "What a room view needs, loaded once per update."
  @type room :: %{
          id: String.t(),
          name: String.t(),
          reading: RoomReading.t(),
          quantities: [RoomReading.quantity()],
          verdict: {Sensors.level(), [RoomReading.quantity()]} | nil,
          hint: [:cools | :warms | :dries | :humidifies] | nil
        }

  @doc """
  Each room's anchor on `/sensors`, e.g. `room-wohnzimmer`. Names that read the same once
  umlauts and punctuation are gone (`Küche`, `Kueche`) get `-2`, `-3` in config order.
  """
  @spec anchors([String.t()]) :: %{String.t() => String.t()}
  def anchors(names) do
    {anchors, _taken} =
      Enum.reduce(names, {%{}, MapSet.new()}, fn name, {anchors, taken} ->
        anchor = unused("room-" <> slug(name), taken)
        {Map.put(anchors, name, anchor), MapSet.put(taken, anchor)}
      end)

    anchors
  end

  defp unused(anchor, taken, n \\ 1) do
    candidate = if n == 1, do: anchor, else: "#{anchor}-#{n}"
    if MapSet.member?(taken, candidate), do: unused(anchor, taken, n + 1), else: candidate
  end

  defp slug(name) do
    name
    |> String.downcase()
    |> String.replace(
      ["ä", "ö", "ü", "ß"],
      &Map.fetch!(%{"ä" => "ae", "ö" => "oe", "ü" => "ue", "ß" => "ss"}, &1)
    )
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @spec label(RoomReading.quantity()) :: String.t()
  def label(quantity), do: Map.fetch!(@labels, quantity)

  @spec unit(RoomReading.quantity()) :: String.t() | nil
  def unit(quantity), do: @units[quantity]

  @spec precision(RoomReading.quantity()) :: non_neg_integer
  def precision(quantity), do: Map.get(@precision, quantity, 0)

  @doc "Quantities in words, PM sizes as one „Feinstaub“: „CO₂, Feinstaub und VOC“."
  @spec groups([RoomReading.quantity()]) :: String.t()
  def groups(quantities),
    do: quantities |> Enum.map(&Map.fetch!(@groups, &1)) |> Enum.uniq() |> sentence()

  @spec level_word(RoomReading.quantity(), number | nil) :: String.t() | nil
  def level_word(quantity, value), do: word(quantity, Sensors.level(quantity, value), value)

  defp word(_quantity, nil, _value), do: nil
  defp word(quantity, :good, _value) when quantity in [:temperature, :humidity], do: "angenehm"

  defp word(:temperature, :warn, value),
    do: if(value < hd(Sensors.level_limits(:temperature)), do: "zu kühl", else: "zu warm")

  defp word(:humidity, _level, value),
    do:
      if(value < Enum.at(Sensors.level_limits(:humidity), 1), do: "zu trocken", else: "zu feucht")

  defp word(quantity, :good, _value) when quantity in [:voc_index, :nox_index], do: "normal"
  defp word(_quantity, :good, _value), do: "gut"
  defp word(_quantity, :warn, _value), do: "erhöht"
  defp word(_quantity, :bad, _value), do: "hoch"

  @doc """
  The air verdict as a headline. „Luft gut“ needs all of CO₂, PM2.5, PM10, VOC and NOx;
  with fewer known it names what was judged: „CO₂ gut“, „CO₂ und Feinstaub gut“.
  """
  @spec verdict_word({Sensors.level(), [RoomReading.quantity()]} | nil) :: String.t()
  def verdict_word(nil), do: "Keine aktuellen Werte"
  def verdict_word({:warn, _quantities}), do: "Bald lüften"
  def verdict_word({:bad, _quantities}), do: "Jetzt lüften"

  def verdict_word({:good, quantities}) do
    if @verdict_quantities -- quantities == [], do: "Luft gut", else: "#{groups(quantities)} gut"
  end

  @doc """
  What the verdict rests on: the culprits („CO₂ und VOC hoch“), or for a good verdict what the
  room measures but has no value for right now: „VOC und NOx in der Anlaufphase“ while a fresh
  SEN66 starts up, else „ohne Feinstaub, VOC und NOx“ — unless an alert already tells
  (`alerted: true`).
  """
  @spec verdict_reason({Sensors.level(), [RoomReading.quantity()]} | nil, map, keyword) ::
          String.t() | nil
  def verdict_reason(verdict, room, opts \\ [])
  def verdict_reason(nil, _room, _opts), do: nil
  def verdict_reason({:warn, culprits}, _room, _opts), do: "#{groups(culprits)} erhöht"
  def verdict_reason({:bad, culprits}, _room, _opts), do: "#{groups(culprits)} hoch"

  def verdict_reason({:good, _known}, %{quantities: quantities, reading: reading}, opts) do
    unknown = missing(reading, Enum.filter(@verdict_quantities, &(&1 in quantities)))

    cond do
      unknown == [] or opts[:alerted] ->
        nil

      reading.lead_fresh and unknown -- @start_up_quantities == [] ->
        "#{groups(unknown)} in der Anlaufphase"

      true ->
        "ohne #{groups(unknown)}"
    end
  end

  defp missing(%RoomReading{values: values}, quantities),
    do: Enum.filter(quantities, &is_nil(values[&1]))

  @doc """
  The ventilation hint in words and whether it warns: drying a room that is already too dry
  (or humidifying a damp one) does harm. `short: true` gives the room strip's form.
  """
  @spec hint_text([:cools | :warms | :dries | :humidifies] | nil, RoomReading.t(), keyword) ::
          {String.t(), :good | :warn} | nil
  def hint_text(effects, reading, opts \\ [])
  def hint_text(nil, _reading, _opts), do: nil

  def hint_text(effects, %RoomReading{values: values}, opts) do
    humidity = values.humidity && values.humidity.value

    {helpful, harmful} =
      Enum.split_with(effects, fn
        :dries -> humidity > 60
        :humidifies -> humidity < 40
        :cools -> true
        :warms -> false
      end)

    helpful_words =
      Enum.map(
        helpful,
        &Map.fetch!(%{cools: "kühlt", dries: "trocknet", humidifies: "befeuchtet"}, &1)
      )

    case {harmful, opts[:short]} do
      {[], _short} ->
        {"Lüften " <> sentence(helpful_words), :good}

      {harmful, true} ->
        {"Lüften " <> sentence(helpful_words ++ Enum.map(harmful, &harm_short/1)), :warn}

      {harmful, _long} ->
        lead =
          case {helpful, harmful} do
            {[], harmful} -> "Lüften " <> sentence(Enum.map(harmful, &harm/1))
            {_helpful, [effect]} -> "Lüften #{sentence(helpful_words)}, #{harm_but(effect)}"
          end

        {"#{lead} – der Raum ist schon #{sentence(Enum.map(harmful, &room_state/1))}", :warn}
    end
  end

  defp harm(:warms), do: "wärmt"
  defp harm(:dries), do: "trocknet weiter aus"
  defp harm(:humidifies), do: "befeuchtet weiter"

  defp room_state(:warms), do: "warm"
  defp room_state(:dries), do: "zu trocken"
  defp room_state(:humidifies), do: "zu feucht"

  defp harm_but(:warms), do: "wärmt aber"
  defp harm_but(:dries), do: "trocknet aber weiter aus"
  defp harm_but(:humidifies), do: "befeuchtet aber weiter"

  defp harm_short(:warms), do: "wärmt"
  defp harm_short(:dries), do: "trocknet aus"
  defp harm_short(:humidifies), do: "befeuchtet weiter"

  @doc """
  The balcony values beside the hint; while the hint dries or humidifies, also the balcony
  air's humidity at the room's temperature, as the tile shows it.
  """
  @spec balcony_text(Reading.t(), [atom] | nil, RoomReading.t()) :: String.t()
  def balcony_text(%Reading{} = outdoor, effects, %RoomReading{values: values}) do
    raw =
      "Balkon #{number(outdoor.temperature, precision: 1, unit: "°C")} · #{number(outdoor.humidity, unit: "%")}"

    with true <- Enum.any?(effects || [], &(&1 in [:dries, :humidifies])),
         %{value: celsius} <- values.temperature,
         humidity when is_number(humidity) <- Sensors.humidity_at(outdoor, celsius) do
      "#{raw} · bei #{number(celsius, precision: precision(:temperature), unit: unit(:temperature))}: #{number(humidity, unit: "%")}"
    else
      _no_humidity_effect -> raw
    end
  end

  @doc "Device status flags as „problem – consequence“, the two CO₂ errors as one."
  @spec device_status_text([atom]) :: [String.t()]
  def device_status_text(flags) do
    flags
    |> Enum.map(fn flag ->
      case Map.fetch!(@device_status, flag) do
        {problem, nil} -> problem
        {problem, consequence} -> "#{problem} – #{consequence}"
      end
    end)
    |> Enum.uniq()
  end

  defp sentence([one]), do: one
  defp sentence(words), do: Enum.join(Enum.drop(words, -1), ", ") <> " und " <> List.last(words)

  defp level_text(level), do: @level_texts[level]
  defp verdict_level(verdict), do: verdict && elem(verdict, 0)

  attr :rooms, :list, required: true

  def room_strip(assigns) do
    assigns =
      assign(assigns,
        entries:
          for room <- assigns.rooms do
            co2 = room.reading.values[:co2]
            hint = hint_text(room.hint, room.reading, short: true)
            %{room: room, co2: co2 && co2.value, hint: hint}
          end
      )

    ~H"""
    <nav class="card mb-4 room-air-strip" aria-label="Räume">
      <div class="list-group list-group-flush">
        <a
          :for={entry <- @entries}
          href={"##{entry.room.id}"}
          class="list-group-item list-group-item-action room-air-strip-row"
        >
          <strong class="room-air-strip-name text-body">{entry.room.name}</strong>
          <span class={[
            "room-air-strip-verdict fw-semibold",
            level_text(verdict_level(entry.room.verdict))
          ]}>
            {verdict_word(entry.room.verdict)}
          </span>
          <span class="room-air-strip-co2 tabular-nums text-nowrap">
            {entry.co2 && number(entry.co2, unit: "ppm")}
          </span>
          <span class={[
            "room-air-strip-hint small",
            if(entry.hint && elem(entry.hint, 1) == :warn,
              do: "text-warning-emphasis",
              else: "text-body-secondary"
            )
          ]}>
            {entry.hint && elem(entry.hint, 0)}
          </span>
          <.chevron class="room-air-strip-chevron" />
        </a>
      </div>
    </nav>
    """
  end

  attr :class, :string, default: nil

  defp chevron(assigns) do
    ~H"""
    <svg class={["room-air-chevron", @class]} viewBox="0 0 16 16" aria-hidden="true">
      <path
        d="M6 3l5 5-5 5"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :room, :map, required: true, doc: "see `t:room/0`"
  attr :first, :boolean, default: true
  attr :latest, :map, required: true, doc: "each sensor's newest reading by id"
  attr :outdoor, Reading, default: nil
  attr :balcony, :boolean, default: false, doc: "an outdoor meter is configured"
  attr :now, DateTime, required: true
  attr :zone, :string, required: true

  def room(assigns) do
    ~H"""
    <section
      class={["room-air mb-4", !@first && "mt-5 pt-4 border-top"]}
      id={@room.id}
      aria-labelledby={"#{@room.id}-name"}
    >
      <h2 class="h3 mb-1" id={"#{@room.id}-name"}>{@room.name}</h2>
      <.sources room={@room} latest={@latest} now={@now} zone={@zone} />
      <.device_alert reading={@room.reading} />
      <.lead_alert room={@room} latest={@latest} now={@now} zone={@zone} />
      <.hero :if={:co2 in @room.quantities} room={@room} outdoor={@outdoor} balcony={@balcony} />
      <.tiles room={@room} />

      <h3 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Verlauf · letzte 24 h</h3>
      <.charts room={@room} />
      <.pm_split room={@room} />
      <.sensors_card reading={@room.reading} latest={@latest} now={@now} zone={@zone} />
    </section>
    """
  end

  attr :room, :map, required: true
  attr :latest, :map, required: true
  attr :now, DateTime, required: true
  attr :zone, :string, required: true

  defp sources(assigns) do
    reading = assigns.room.reading

    assigns =
      assign(assigns,
        entries:
          for sensor <- [reading.lead | reading.stand_ins] do
            latest = assigns.latest[sensor.id]
            {freshness, age} = freshness(sensor, latest, assigns.now, assigns.zone)

            %{
              role: if(sensor == reading.lead, do: "Leitsensor", else: "Ersatzsensor"),
              sensor: sensor,
              age: age,
              stale?: freshness != :fresh,
              status: if(freshness == :fresh, do: status(sensor, latest))
            }
          end
      )

    ~H"""
    <ul class="room-air-sources list-unstyled d-md-flex flex-wrap column-gap-4 small text-body-secondary mb-3">
      <li :for={entry <- @entries}>
        <%!-- Each separator ends its item, so a wrapped line never starts with one. --%>
        <span class="text-nowrap">
          {entry.role}: <span class="text-body fw-semibold">{entry.sensor.name}</span> ·
        </span>
        <span class="text-nowrap">
          <span class={entry.stale? && "text-warning-emphasis"}>{entry.age}</span>{if entry.status,
            do: " ·"}
        </span>
        <span :if={entry.status} class="text-nowrap">
          <span class={tone_text(elem(entry.status, 1))}>{elem(entry.status, 0)}</span>
        </span>
      </li>
    </ul>
    """
  end

  defp freshness(_sensor, nil, _now, _zone), do: {:none, "noch keine Daten"}

  defp freshness(sensor, %Reading{} = latest, now, zone) do
    if RoomReading.fresh?(sensor, latest, now),
      do: {:fresh, age_label(latest, now)},
      else: {:stale, "keine Daten seit #{since(latest.taken_at, now, zone)}"}
  end

  # A fresh SEN66's device status in a word and a tone; a battery stands in the page's alert.
  defp status(%Sensor{type: :sen66}, latest) do
    case Sensors.device_status_flags(latest.device_status) do
      [] -> {"in Ordnung", nil}
      [:fan_speed_warning] -> {"Warnung", :warn}
      _errors -> {"Fehler", :bad}
    end
  end

  defp status(_sensor, _latest), do: nil

  defp tone_text(:warn), do: "text-warning-emphasis"
  defp tone_text(:bad), do: "text-danger-emphasis"
  defp tone_text(_tone), do: nil

  defp since(taken_at, now, zone) do
    if DateTime.diff(now, taken_at) < 20 * 3600,
      do: clock(taken_at, zone),
      else: day_month(DateTime.shift_zone!(taken_at, zone))
  end

  attr :reading, RoomReading, required: true

  defp device_alert(assigns) do
    flags = assigns.reading.device_status

    assigns =
      assign(assigns,
        problems: device_status_text(flags),
        kind: if(flags -- [:fan_speed_warning] == [], do: "warning", else: "danger")
      )

    ~H"""
    <div :if={@problems != []} class={"alert alert-#{@kind} mb-3"} role="alert">
      <strong>{@reading.lead.name} meldet:</strong> {Enum.join(@problems, "; ")}.
    </div>
    """
  end

  attr :room, :map, required: true
  attr :latest, :map, required: true
  attr :now, DateTime, required: true
  attr :zone, :string, required: true

  defp lead_alert(assigns) do
    %{reading: reading, quantities: quantities} = assigns.room
    lead = reading.lead

    assigns =
      assign(assigns,
        message:
          case freshness(lead, assigns.latest[lead.id], assigns.now, assigns.zone) do
            {:fresh, _age} -> nil
            {_stale, since} -> "#{lead.name}: #{since}" <> consequence(reading, quantities)
          end
      )

    ~H"""
    <div :if={@message} class="alert alert-warning mb-3" role="alert">{@message}.</div>
    """
  end

  defp consequence(%RoomReading{values: values} = reading, quantities) do
    standing_in = for q <- quantities, match?(%{source: :stand_in}, values[q]), do: q

    parts =
      Enum.reject(
        [
          standing_in != [] &&
            "#{groups(standing_in)} #{verb(standing_in, "kommt", "kommen")} vom Ersatzsensor",
          (unknown = missing(reading, quantities)) != [] &&
            "#{groups(unknown)} #{verb(unknown, "fehlt", "fehlen")}"
        ],
        &(&1 == false)
      )

    if parts == [], do: "", else: " – " <> Enum.join(parts, ", ")
  end

  defp verb(quantities, one, many),
    do:
      if(quantities |> Enum.map(&@groups[&1]) |> Enum.uniq() |> length() == 1,
        do: one,
        else: many
      )

  attr :room, :map, required: true
  attr :outdoor, Reading, default: nil
  attr :balcony, :boolean, required: true

  defp hero(assigns) do
    reading = assigns.room.reading
    co2 = reading.values.co2

    assigns =
      assign(assigns,
        co2: co2,
        level: verdict_level(assigns.room.verdict),
        reason:
          verdict_reason(assigns.room.verdict, assigns.room, alerted: not reading.lead_fresh),
        hint: hint_text(assigns.room.hint, reading),
        hint?: assigns.room.hint != nil or (assigns.balcony and is_nil(assigns.outdoor))
      )

    ~H"""
    <div class="card mb-3 room-air-hero">
      <div class="card-body">
        <div class="row g-3 align-items-start">
          <div class="col-12 col-md-auto pe-md-3 d-flex align-items-start gap-3">
            <.co2_gauge :if={@co2} ppm={@co2.value} />
            <div class="stat">
              <span class="stat-label">CO₂</span>
              <span class="text-nowrap">
                <span class="stat-value fs-1">{number(@co2 && @co2.value)}</span>
                <span :if={@co2} class="fs-5 fw-semibold">ppm</span>
              </span>
              <span :if={@co2 && @co2.source == :stand_in} class="small text-body-secondary">
                vom Ersatzsensor
              </span>
            </div>
          </div>
          <div class="col-12 col-md align-self-stretch room-air-hero-column">
            <div class="stat" id={"#{@room.id}-verdict"}>
              <span class="stat-label">Lüftungsempfehlung</span>
              <span class={["stat-value fs-2", level_text(@level)]}>{verdict_word(@room.verdict)}</span>
              <span :if={@reason} class="small text-body-secondary">{@reason}</span>
            </div>
          </div>
          <div :if={@hint?} class="col-md d-none d-md-block align-self-stretch room-air-hero-column">
            <div class="stat">
              <span class="stat-label">Lüftungshinweis</span>
              <.hint_lines hint={@hint} outdoor={@outdoor} room={@room} />
            </div>
          </div>
        </div>
      </div>
      <div :if={@hint?} class="card-footer d-md-none" id={"#{@room.id}-hint"}>
        <span class="small fw-semibold text-uppercase text-body-secondary me-1">Lüftungshinweis</span>
        <.hint_lines hint={@hint} outdoor={@outdoor} room={@room} />
      </div>
    </div>
    """
  end

  attr :hint, :any, required: true
  attr :outdoor, Reading, default: nil
  attr :room, :map, required: true

  defp hint_lines(assigns) do
    ~H"""
    <%= if @hint do %>
      <strong class={elem(@hint, 1) == :warn && "text-warning-emphasis"}>{elem(@hint, 0)}</strong>
      <span class="d-block small text-body-secondary">
        {balcony_text(@outdoor, @room.hint, @room.reading)}
      </span>
    <% else %>
      <span class="small text-body-secondary">keine aktuellen Balkonwerte</span>
    <% end %>
    """
  end

  attr :quantity, :atom, required: true
  attr :value, :any, required: true

  def level_badge(assigns) do
    level = Sensors.level(assigns.quantity, assigns.value)

    assigns =
      assign(assigns,
        class: @level_badges[level],
        word: level_word(assigns.quantity, assigns.value)
      )

    ~H"""
    <span :if={@word} class={["badge rounded-pill", @class]}>{@word}</span>
    """
  end

  attr :room, :map, required: true

  defp tiles(assigns) do
    %{reading: reading, quantities: quantities} = assigns.room
    shown = Enum.filter(@tile_quantities, &(&1 in quantities and reading.values[&1]))

    assigns =
      assign(assigns, quantities: shown, columns: "row-cols-md-#{tile_columns(length(shown))}")

    ~H"""
    <div :if={@quantities != []} class={["row row-cols-2 g-2 mb-3", @columns]}>
      <.tile
        :for={quantity <- @quantities}
        data-quantity={quantity}
        number={number(@room.reading.values[quantity].value, precision: precision(quantity))}
        unit={unit(quantity)}
        caption={tile_caption(quantity, @room.reading.values[quantity])}
      >
        <:title><.tile_label quantity={quantity} /></:title>
        <:badge>
          <.level_badge quantity={quantity} value={@room.reading.values[quantity].value} />
        </:badge>
      </.tile>
    </div>
    """
  end

  defp tile_columns(count) when count in 1..4, do: count
  defp tile_columns(_count), do: 3

  attr :quantity, :atom, required: true

  # The NOx's x keeps its case under the label's uppercase.
  defp tile_label(%{quantity: :nox_index} = assigns) do
    ~H"""
    NO<span class="text-lowercase">x</span>-Index
    """
  end

  defp tile_label(assigns) do
    assigns =
      assign(assigns,
        text:
          Map.get(
            %{pm2_5: "Feinstaub PM2,5", pm10: "Feinstaub PM10", voc_index: "VOC-Index"},
            assigns.quantity,
            label(assigns.quantity)
          )
      )

    ~H"""
    {@text}
    """
  end

  # The index meanings stand in the charts' subtitles.
  defp tile_caption(_quantity, %{source: :stand_in}), do: "vom Ersatzsensor"
  defp tile_caption(_quantity, _value), do: nil

  attr :room, :map, required: true

  defp pm_split(assigns) do
    assigns = assign(assigns, :bins, pm_bins(assigns.room.reading.values))

    ~H"""
    <section :if={@bins} class="card mb-3" aria-labelledby={"#{@room.id}-pm-split"}>
      <div class="card-body">
        <h4 class="card-title" id={"#{@room.id}-pm-split"}>Feinstaub nach Größe</h4>
        <p class="card-subtitle">µg/m³ · Anteile an PM10, aktuelle Messung</p>
        <div class="progress-stacked pm-split mb-2" style="height: 1rem">
          <div
            :for={bin <- @bins}
            :if={bin.share > 0}
            class="progress h-100"
            role="progressbar"
            style={"width: #{bin.share}%"}
            aria-label={bin.label}
            aria-valuenow={bin.share}
            aria-valuemin="0"
            aria-valuemax="100"
          >
            <div class="progress-bar" data-bin={bin.index}></div>
          </div>
        </div>
        <ul class="list-unstyled d-flex flex-wrap column-gap-4 row-gap-1 small tabular-nums mb-0">
          <li :for={bin <- @bins} class="d-flex align-items-center gap-2 text-nowrap">
            <span class="badge rounded-pill legend-dot pm-split-key" data-bin={bin.index}></span>
            <span>{bin.label}</span>
            <span class="text-body-secondary">
              {number(bin.value, precision: 1)} · {number(bin.share, unit: "%")}
            </span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  @doc "The particle sizes' shares of PM10; nil without all four values or without any dust."
  @spec pm_bins(%{RoomReading.quantity() => map | nil}) :: [map] | nil
  def pm_bins(values) do
    pm = for {_label, _below, upper} <- @pm_bins, into: %{}, do: {upper, values[upper]}

    if Enum.all?(pm, fn {_q, value} -> value end) do
      @pm_bins
      |> Enum.with_index(1)
      |> Enum.map(fn {{label, below, upper}, index} ->
        %{index: index, label: label, value: max(pm[upper].value - lower_value(pm, below), 0.0)}
      end)
      |> with_shares()
    end
  end

  defp lower_value(_pm, nil), do: 0
  defp lower_value(pm, below), do: pm[below].value

  defp with_shares(bins) do
    total = bins |> Enum.map(& &1.value) |> Enum.sum()
    if total > 0, do: Enum.map(bins, &Map.put(&1, :share, round(&1.value / total * 100)))
  end

  attr :room, :map, required: true

  defp charts(assigns) do
    quantities = assigns.room.quantities
    stand_ins? = assigns.room.reading.stand_ins != []

    assigns =
      assign(assigns,
        co2?: :co2 in quantities,
        stand_ins?: stand_ins?,
        cards:
          for card <- chart_cards(), card.needs in quantities do
            Map.put(card, :stand_ins?, stand_ins? and card.key in ["temperature", "humidity"])
          end
      )

    ~H"""
    <div id={"#{@room.id}-charts"} phx-hook="RoomAirChart" data-room={@room.id}>
      <section :if={@co2?} class="card mb-3">
        <div class="card-body">
          <h4 class="card-title">CO₂</h4>
          <p class="card-subtitle">ppm</p>
          <.chart_key stand_ins?={@stand_ins?} />
          <div
            class="chart-frame chart-frame-prominent"
            id={"#{@room.id}-co2-chart"}
            phx-update="ignore"
          >
            <canvas data-chart="co2"></canvas>
          </div>
        </div>
      </section>

      <div :if={@cards != []} class="row row-cols-1 row-cols-md-2 g-3 mb-3">
        <div
          :for={{card, index} <- Enum.with_index(@cards)}
          class={["col", odd_last?(@cards, index) && "col-md-12"]}
        >
          <section class="card h-100">
            <div class="card-body d-flex flex-column">
              <h4 class="card-title">{card.title}</h4>
              <p class="card-subtitle">{card.subtitle}</p>
              <.chart_key
                series={card[:series] || []}
                limits={card[:limits]}
                band={card[:band]}
                gaps?={card[:gaps?] || false}
                stand_ins?={card.stand_ins?}
                reserve
              />
              <div
                class="chart-frame chart-frame-compact mt-auto"
                id={"#{@room.id}-#{card.key}-chart"}
                phx-update="ignore"
              >
                <canvas data-chart={card.key}></canvas>
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  # An odd chart out takes the whole row instead of leaving half of it empty.
  defp odd_last?(cards, index), do: rem(length(cards), 2) == 1 and index == length(cards) - 1

  defp chart_cards do
    [
      %{
        key: "pm",
        needs: :pm2_5,
        title: "Feinstaub",
        subtitle: "µg/m³",
        series: [{1, label(:pm2_5)}, {2, label(:pm10)}],
        limits: "Grenzen für PM2,5",
        gaps?: true
      },
      %{
        key: "voc_index",
        needs: :voc_index,
        title: "VOC-Index",
        subtitle: @voc_meaning,
        gaps?: true
      },
      %{
        key: "nox_index",
        needs: :nox_index,
        title: "NOx-Index",
        subtitle: "1 = Normalzustand",
        gaps?: true
      },
      %{key: "temperature", needs: :temperature, title: "Temperatur", subtitle: "°C"},
      %{
        key: "humidity",
        needs: :humidity,
        title: "Luftfeuchte",
        subtitle: "%",
        band: "angenehm 40–60 %"
      }
    ]
  end

  attr :series, :list, default: []
  attr :limits, :string, default: nil
  attr :band, :string, default: nil
  attr :gaps?, :boolean, default: false
  attr :stand_ins?, :boolean, default: false
  attr :reserve, :boolean, default: false, doc: "keeps the line when empty"

  defp chart_key(assigns) do
    ~H"""
    <ul
      :if={@reserve || @series != [] || @limits || @band || @gaps? || @stand_ins?}
      class="chart-key list-inline small text-body-secondary mb-2"
    >
      <li :for={{tone, name} <- @series} class="list-inline-item">
        <span class="chart-key-line" style={"--tone: var(--viz-#{tone})"}></span>{name}
      </li>
      <li :if={@limits} class="list-inline-item">
        <span class="chart-key-limit"></span>{@limits}
      </li>
      <li :if={@band} class="list-inline-item"><span class="chart-key-band"></span>{@band}</li>
      <li :if={@gaps?} class="list-inline-item"><span class="chart-key-gap"></span>keine Messung</li>
      <li :if={@stand_ins?} class="list-inline-item">
        <span class="chart-key-stand-in"></span>Ersatzsensor
      </li>
    </ul>
    """
  end

  attr :reading, RoomReading, required: true
  attr :latest, :map, required: true
  attr :now, DateTime, required: true
  attr :zone, :string, required: true

  defp sensors_card(assigns) do
    reading = assigns.reading

    assigns =
      assign(assigns,
        sensors:
          for sensor <- [reading.lead | reading.stand_ins] do
            {sensor, if(sensor == reading.lead, do: "Leitsensor", else: "Ersatzsensor"),
             assigns.latest[sensor.id]}
          end
      )

    ~H"""
    <section class="card mb-3">
      <div class="card-body">
        <h4 class="card-title">Sensoren</h4>
        <div class="row row-cols-1 row-cols-md-2 g-4">
          <div :for={{sensor, role, latest} <- @sensors} class="col room-air-sensor">
            <div class="d-flex align-items-baseline gap-2 mb-1">
              <strong>{sensor.name}</strong>
              <span class="badge border">{role}</span>
            </div>
            <dl class="row small mb-0">
              <dt class="col-5 fw-normal text-body-secondary">Letzte Messung</dt>
              <dd class="col-7 mb-1 tabular-nums">{last_reading(latest, @now, @zone)}</dd>
              <%= if sensor.type == :sen66 do %>
                <dt class="col-5 fw-normal text-body-secondary">Status</dt>
                <dd class={[
                  "col-7 mb-1",
                  tone_text(elem(status_text(sensor, latest, @now, @zone), 1))
                ]}>
                  {elem(status_text(sensor, latest, @now, @zone), 0)}
                </dd>
                <dt class="col-5 fw-normal text-body-secondary">Firmware</dt>
                <dd class="col-7 mb-1">{(latest && latest.firmware_version) || "—"}</dd>
              <% end %>
              <%= if latest && latest.battery_pct do %>
                <dt class="col-5 fw-normal text-body-secondary">Batterie</dt>
                <dd class={[
                  "col-7 mb-1 tabular-nums",
                  Sensors.battery_low?(latest) && "text-warning-emphasis"
                ]}>
                  {number(latest.battery_pct, unit: "%")}
                </dd>
              <% end %>
              <dt class="col-5 fw-normal text-body-secondary">
                {if sensor.type == :sen66, do: "Seriennummer", else: "Geräte-ID"}
              </dt>
              <dd class="col-7 mb-1 font-monospace text-break">{sensor.id}</dd>
            </dl>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp last_reading(nil, _now, _zone), do: "—"

  defp last_reading(%Reading{taken_at: taken_at} = latest, now, zone),
    do: "#{since(taken_at, now, zone)} · #{age_label(latest, now)}"

  defp status_text(sensor, latest, now, zone) do
    case freshness(sensor, latest, now, zone) do
      {:fresh, _age} ->
        flags = Sensors.device_status_flags(latest.device_status)
        {_word, tone} = status(sensor, latest)

        case device_status_text(flags) do
          [] -> {"in Ordnung", nil}
          problems -> {Enum.join(problems, "; "), tone}
        end

      {_stale, since} ->
        {since, :warn}
    end
  end

  attr :tile, :map,
    required: true,
    doc: "`%{id, name, reading, quantities, verdict, now}` of the room"

  def dashboard_tile(assigns) do
    %{reading: reading, verdict: verdict, now: now} = assigns.tile
    co2 = reading.values.co2
    level = verdict_level(verdict)

    assigns =
      assign(assigns,
        co2: co2,
        level: level,
        tint: @level_tints[level],
        reason: verdict_reason(verdict, assigns.tile),
        age: co2 && age_text(co2.taken_at, now)
      )

    ~H"""
    <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Raumluft</h2>
    <.link
      navigate={~p"/sensors" <> "#" <> @tile.id}
      id="room_air_tile"
      class={["card text-decoration-none text-body mb-3 room-air-tile", @tint]}
    >
      <div class="card-body p-3 d-flex align-items-stretch gap-3">
        <div class="flex-grow-1 room-air-tile-grid">
          <div class="stat room-air-tile-verdict">
            <span class="stat-label">{@tile.name}</span>
            <span class={["stat-value fs-2", level_text(@level)]}>
              {verdict_word(@tile.verdict)}
            </span>
            <span :if={@reason} class="small text-body-secondary">{@reason}</span>
          </div>
          <div class="stat text-end room-air-tile-co2">
            <span class="stat-label">CO₂</span>
            <span class="stat-value fs-2 text-nowrap">{number(@co2 && @co2.value)}
            <span :if={@co2} class="fs-5 fw-semibold">ppm</span></span>
          </div>
          <div :if={@co2} class="small text-body-secondary room-air-tile-meta">
            <span class="text-nowrap"><.level_badge quantity={:co2} value={@co2.value} /></span>
            <span :if={@co2.source == :stand_in} class="text-nowrap">Ersatzsensor ·</span>
            <span class="text-nowrap">{@age}</span>
          </div>
        </div>
        <.chevron class="room-air-tile-chevron align-self-center" />
      </div>
    </.link>
    """
  end

  defp age_text(taken_at, now) do
    case DateTime.diff(now, taken_at) do
      seconds when seconds < 60 -> "vor\u00A0#{max(seconds, 0)}\u00A0s"
      seconds when seconds < 3600 -> "vor\u00A0#{div(seconds, 60)}\u00A0Min"
      seconds -> "vor\u00A0#{div(seconds, 3600)}\u00A0h"
    end
  end
end
