defmodule ZiwoasWeb.RoomAirComponents do
  @moduledoc """
  A room's air on `/sensors` and the dashboard (CONTEXT.md, "Room air"): its room reading with
  each value's source, the air verdict, the ventilation hint and the sensors behind them.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.SensorsComponents, only: [co2_gauge: 1, co2_label: 1, age_label: 2]

  alias Ziwoas.Config.Sensor
  alias Ziwoas.Sensors
  alias Ziwoas.Sensors.{Reading, RoomReading}
  alias ZiwoasWeb.Charts.RoomAir, as: RoomAirCharts

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
    humidity: "Luftfeuchte"
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
  @level_tones %{good: :success, warn: :warning, bad: :error}
  @verdict_tones %{warn: :warning, bad: :error}
  @verdict_inks %{warn: "text-warning-ink", bad: "text-error-ink"}
  @device_status %{
    fan_speed_warning: {"Lüfterdrehzahl weicht ab", "Feinstaubwerte können ungenau sein"},
    fan_error: {"Lüfter ausgefallen", "Feinstaubwerte fehlen oder sind falsch"},
    rht_error:
      {"Temperatur- und Feuchtesensor gestört", "Temperatur und Luftfeuchte sind unsicher"},
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
  # Four bins spread over the five steps of the sequential ramp.
  @pm_steps %{1 => 1, 2 => 2, 3 => 4, 4 => 5}

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

  defp verdict_level(verdict), do: verdict && elem(verdict, 0)

  attr :level, :atom, required: true, doc: "`:good`, `:warn`, `:bad` or nil"
  attr :style, :atom, default: :dot, doc: "`:dot` or `:text`; the alarm level is always solid"
  attr :rest, :global
  slot :inner_block, required: true

  defp level_badge_for(assigns) do
    assigns =
      assign(assigns,
        tone: Map.get(@level_tones, assigns.level, :neutral),
        style:
          if(assigns.level == :bad and assigns.style == :dot, do: :solid, else: assigns.style)
      )

    ~H"""
    <.badge tone={@tone} style={@style} data-level={@level} {@rest}>
      {render_slot(@inner_block)}
    </.badge>
    """
  end

  attr :rooms, :list, required: true

  def room_strip(assigns) do
    assigns =
      assign(assigns,
        entries:
          for room <- assigns.rooms do
            co2 = room.reading.values[:co2]
            hint = hint_text(room.hint, room.reading, short: true)
            %{room: room, co2: co2 && number(co2.value, unit: "ppm"), hint: hint}
          end
      )

    ~H"""
    <nav id="room-strip" aria-labelledby="room-strip-heading">
      <.section_heading id="room-strip-heading">Räume</.section_heading>
      <.list>
        <.list_row
          :for={entry <- @entries}
          id={"#{entry.room.id}-strip"}
          title={entry.room.name}
          href={"##{entry.room.id}"}
          trailing_on_phone={:title}
        >
          <:meta :if={entry.co2 || entry.hint}>
            <span class="tabular-nums">{entry.co2}</span><.meta_sep :if={entry.co2 && entry.hint} /><.hint_word
              :if={entry.hint}
              hint={entry.hint}
            />
          </:meta>
          <:trailing>
            <.level_badge_for level={verdict_level(entry.room.verdict)}>
              {verdict_word(entry.room.verdict)}
            </.level_badge_for>
          </:trailing>
        </.list_row>
      </.list>
    </nav>
    """
  end

  attr :hint, :any, required: true

  defp hint_word(%{hint: {_text, :warn}} = assigns) do
    ~H"""
    <.level_badge_for level={:warn} style={:text}>{elem(@hint, 0)}</.level_badge_for>
    """
  end

  defp hint_word(assigns), do: ~H"{elem(@hint, 0)}"

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
      class={[
        "flex scroll-mt-20 flex-col gap-8",
        !@first && "border-t border-base-content/10 pt-8"
      ]}
      id={@room.id}
      aria-labelledby={"#{@room.id}-name"}
    >
      <div class="flex flex-col gap-4 md:gap-6">
        <div>
          <.section_heading id={"#{@room.id}-name"} class="mb-1">{@room.name}</.section_heading>
          <.sources room={@room} latest={@latest} now={@now} zone={@zone} />
        </div>
        <.device_alert room={@room} />
        <.lead_alert room={@room} latest={@latest} now={@now} zone={@zone} />
        <.hero :if={:co2 in @room.quantities} room={@room} />
        <.hint room={@room} outdoor={@outdoor} balcony={@balcony} />
        <.tiles room={@room} />
      </div>

      <section aria-labelledby={"#{@room.id}-history"} class="flex flex-col gap-4 md:gap-6">
        <.section_heading id={"#{@room.id}-history"} level={3} class="mb-0">
          Verlauf <span class="font-normal text-base-content/70">letzte 24 h</span>
        </.section_heading>
        <.charts room={@room} />
        <.pm_split room={@room} />
      </section>

      <.sensor_facts room={@room} latest={@latest} now={@now} zone={@zone} />
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
              role: role(sensor, reading),
              sensor: sensor,
              age: age,
              stale?: freshness != :fresh,
              status: if(freshness == :fresh, do: status(sensor, latest))
            }
          end
      )

    ~H"""
    <ul
      id={"#{@room.id}-sources"}
      class="flex flex-wrap gap-x-6 gap-y-1 text-sm text-base-content/70"
    >
      <li :for={entry <- @entries} data-sensor={entry.sensor.id}>
        {entry.role}:
        <span class="font-medium text-base-content">{entry.sensor.name}</span><.meta_sep />
        <%= if entry.stale? do %>
          <.level_badge_for
            level={:warn}
            style={:text}
          >
            {entry.age}
          </.level_badge_for>
        <% else %>
          {entry.age}
        <% end %>
        <.meta_sep :if={entry.status} /><.level_badge_for
          :if={entry.status}
          level={elem(entry.status, 1)}
          style={:text}
        >
          {elem(entry.status, 0)}
        </.level_badge_for>
      </li>
    </ul>
    """
  end

  defp role(sensor, reading),
    do: if(sensor == reading.lead, do: "Leitsensor", else: "Ersatzsensor")

  defp freshness(_sensor, nil, _now, _zone), do: {:none, "noch keine Daten"}

  defp freshness(sensor, %Reading{} = latest, now, zone) do
    if RoomReading.fresh?(sensor, latest, now),
      do: {:fresh, age_label(latest, now)},
      else: {:stale, "keine Daten seit #{since(latest.taken_at, now, zone)}"}
  end

  # A fresh SEN66's device status in a word and a level; a battery stands in the page's alert.
  defp status(%Sensor{type: :sen66}, latest) do
    case Sensors.device_status_flags(latest.device_status) do
      [] -> {"in Ordnung", :good}
      [:fan_speed_warning] -> {"Warnung", :warn}
      _errors -> {"Fehler", :bad}
    end
  end

  defp status(_sensor, _latest), do: nil

  defp since(taken_at, now, zone) do
    if DateTime.diff(now, taken_at) < 20 * 3600,
      do: clock(taken_at, zone),
      else: day_month(DateTime.shift_zone!(taken_at, zone))
  end

  attr :room, :map, required: true

  defp device_alert(assigns) do
    reports = assigns.room.reading.device_status

    warnings_only? =
      Enum.all?(reports, fn {_sensor, flags} -> flags -- [:fan_speed_warning] == [] end)

    assigns =
      assign(assigns,
        reports: for({sensor, flags} <- reports, do: {sensor.name, device_status_text(flags)}),
        tone: if(warnings_only?, do: :warning, else: :error)
      )

    ~H"""
    <.alert :if={@reports != []} id={"#{@room.id}-device-alert"} tone={@tone}>
      <p :for={{name, problems} <- @reports}>
        <span class="font-semibold">{name} meldet:</span> {Enum.join(problems, "; ")}.
      </p>
    </.alert>
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
    <.alert :if={@message} id={"#{@room.id}-lead-alert"} tone={:warning}>{@message}.</.alert>
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

  defp hero(assigns) do
    reading = assigns.room.reading
    co2 = reading.values.co2
    level = verdict_level(assigns.room.verdict)

    assigns =
      assign(assigns,
        co2: co2,
        co2_word?: co2 && not (level == :good and Sensors.co2_level(co2.value) == :good),
        level: level,
        tone: @verdict_tones[level],
        reason:
          verdict_reason(assigns.room.verdict, assigns.room, alerted: not reading.lead_fresh)
      )

    ~H"""
    <div class="setzkasten-stat-grid grid gap-4 md:grid-cols-2 md:gap-6">
      <.stat
        id={"#{@room.id}-co2-now"}
        label="CO₂"
        value={number(@co2 && @co2.value)}
        unit={@co2 && "ppm"}
        size={:sm}
      >
        <:note :if={@co2 && (@co2_word? or @co2.source == :stand_in)}>
          <.level_badge :if={@co2_word?} quantity={:co2} value={@co2.value} />
          <span :if={@co2.source == :stand_in}>vom Ersatzsensor</span>
        </:note>
        <:figure :if={@co2} label={co2_label(@co2.value)}>
          <.co2_gauge ppm={@co2.value} class="w-28" />
        </:figure>
      </.stat>
      <.stat
        id={"#{@room.id}-verdict"}
        label="Lüftungsempfehlung"
        value={verdict_word(@room.verdict)}
        tone={@tone}
        size={:sm}
        data-level={@level}
      >
        <:note :if={@reason}>
          <%= if @level in [:warn, :bad] do %>
            <.level_badge_for level={@level}>{@reason}</.level_badge_for>
          <% else %>
            {@reason}
          <% end %>
        </:note>
      </.stat>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :outdoor, Reading, default: nil
  attr :balcony, :boolean, required: true

  defp hint(assigns) do
    room = assigns.room

    assigns =
      assign(assigns,
        hint: hint_text(room.hint, room.reading),
        shown?: room.hint != nil or (assigns.balcony and is_nil(assigns.outdoor))
      )

    ~H"""
    <%= if @shown? do %>
      <.alert
        :if={@hint}
        id={"#{@room.id}-hint"}
        tone={if elem(@hint, 1) == :warn, do: :warning, else: :neutral}
        icon="wind"
        title={elem(@hint, 0)}
      >
        {balcony_text(@outdoor, @room.hint, @room.reading)}
      </.alert>
      <.alert :if={!@hint} id={"#{@room.id}-hint"} tone={:neutral} icon="wind">
        Kein Lüftungshinweis: keine aktuellen Balkonwerte
      </.alert>
    <% end %>
    """
  end

  attr :quantity, :atom, required: true
  attr :value, :any, required: true

  def level_badge(assigns) do
    assigns =
      assign(assigns,
        level: Sensors.level(assigns.quantity, assigns.value),
        word: level_word(assigns.quantity, assigns.value)
      )

    ~H"""
    <.level_badge_for :if={@word} level={@level}>{@word}</.level_badge_for>
    """
  end

  attr :room, :map, required: true

  defp tiles(assigns) do
    %{reading: reading, quantities: quantities} = assigns.room
    shown = Enum.filter(@tile_quantities, &(&1 in quantities and reading.values[&1]))

    assigns = assign(assigns, quantities: shown, columns: tile_columns(length(shown)))

    ~H"""
    <div
      :if={@quantities != []}
      class={["setzkasten-stat-grid grid grid-cols-2 gap-4 md:gap-6", @columns]}
    >
      <.stat
        :for={quantity <- @quantities}
        data-quantity={quantity}
        label={tile_label(quantity)}
        value={number(@room.reading.values[quantity].value, precision: precision(quantity))}
        unit={unit(quantity)}
        size={:sm}
      >
        <:note>
          <.level_badge quantity={quantity} value={@room.reading.values[quantity].value} />
          <span :if={@room.reading.values[quantity].source == :stand_in}>vom Ersatzsensor</span>
        </:note>
      </.stat>
    </div>
    """
  end

  defp tile_columns(1), do: "md:grid-cols-1"
  defp tile_columns(2), do: "md:grid-cols-2"
  defp tile_columns(4), do: "md:grid-cols-4"
  defp tile_columns(_count), do: "md:grid-cols-3"

  @tile_labels %{
    pm2_5: "Feinstaub PM2,5",
    pm10: "Feinstaub PM10",
    voc_index: "VOC-Index",
    nox_index: "NOx-Index"
  }

  defp tile_label(quantity), do: Map.get(@tile_labels, quantity, label(quantity))

  attr :room, :map, required: true

  defp pm_split(assigns) do
    bins = pm_bins(assigns.room.reading.values)

    assigns =
      assign(assigns,
        bins: bins,
        pm10: bins && assigns.room.reading.values.pm10.value
      )

    ~H"""
    <.card
      :if={@bins}
      id={"#{@room.id}-pm-split"}
      title="Feinstaub nach Größe"
      subtitle="Anteile an PM10 in µg/m³, aktuelle Messung"
      level={4}
    >
      <.share_bar
        id={"#{@room.id}-pm-shares"}
        label="PM10"
        value_label={number(@pm10, precision: 1, unit: "µg/m³")}
        segments={
          for bin <- @bins,
              do: %{
                label: bin.label,
                value: bin.value,
                color: {:seq, bin.step},
                value_label:
                  join_meta([number(bin.value, precision: 1), number(bin.share, unit: "%")])
              }
        }
        data-series={Enum.map_join(@bins, " ", &"seq-#{&1.step}")}
      />
    </.card>
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
        %{
          index: index,
          step: @pm_steps[index],
          label: label,
          value: max(pm[upper].value - lower_value(pm, below), 0.0)
        }
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
    %{quantities: quantities, reading: reading} = assigns.room
    stand_ins? = reading.stand_ins != []
    cards = for card <- chart_cards(), card.needs in quantities, do: card
    paired = Enum.reject(cards, &(&1.key == "co2"))
    # An odd chart out takes the whole row instead of leaving half of it empty.
    odd_last = if rem(length(paired), 2) == 1, do: List.last(paired)

    assigns =
      assign(assigns,
        cards:
          for card <- cards do
            Map.merge(card, %{
              stand_ins?: stand_ins? and card.key in ["co2", "temperature", "humidity"],
              wide?: card.key == "co2" or card == odd_last,
              summary: chart_summary(card, reading)
            })
          end
      )

    ~H"""
    <div id={"#{@room.id}-charts"} class="grid gap-4 md:grid-cols-2 md:gap-6">
      <.chart_card
        :for={card <- @cards}
        id={"#{@room.id}-#{card.key}"}
        class={card.wide? && "md:col-span-2"}
        title={card.title}
        subtitle={card.subtitle}
        summary={card.summary}
        hook="RoomAirChart"
        hook_attrs={%{"data-room" => @room.id, "data-chart" => card.key}}
        height={if card.key == "co2", do: :lg, else: :md}
        level={4}
      >
        <:legend :if={chart_legend?(card)}>
          <.chart_legend card={card} />
        </:legend>
      </.chart_card>
    </div>
    """
  end

  defp chart_summary(card, reading) do
    current =
      for quantity <- card.quantities,
          value = reading.values[quantity],
          do:
            "#{label(quantity)} #{number(value.value, precision: precision(quantity), unit: unit(quantity))}"

    "#{card.title}, letzte 24 Stunden" <>
      if(current == [], do: "", else: "; jetzt " <> Enum.join(current, ", "))
  end

  defp key_series(key, quantities) do
    [chart] = Enum.filter(RoomAirCharts.charts(quantities), &(&1.key == key))

    for %{series: series, label: label} <- chart.series,
        do: %{label: label, color: series, marker: :line}
  end

  defp chart_cards do
    [
      %{key: "co2", needs: :co2, quantities: [:co2], title: "CO₂", subtitle: "ppm"},
      %{
        key: "pm",
        needs: :pm2_5,
        quantities: [:pm2_5, :pm10],
        title: "Feinstaub",
        subtitle: "µg/m³",
        series: key_series(:pm, [:pm2_5, :pm10]),
        limits: "Grenzen für PM2,5",
        gaps?: true
      },
      %{
        key: "voc_index",
        needs: :voc_index,
        quantities: [:voc_index],
        title: "VOC-Index",
        subtitle: @voc_meaning,
        gaps?: true
      },
      %{
        key: "nox_index",
        needs: :nox_index,
        quantities: [:nox_index],
        title: "NOx-Index",
        subtitle: "1 = Normalzustand",
        gaps?: true
      },
      %{
        key: "temperature",
        needs: :temperature,
        quantities: [:temperature],
        title: "Temperatur",
        subtitle: "°C"
      },
      %{
        key: "humidity",
        needs: :humidity,
        quantities: [:humidity],
        title: "Luftfeuchte",
        subtitle: "%",
        band: "angenehm 40–60 %"
      }
    ]
  end

  defp chart_legend?(card),
    do:
      card[:series] != nil or card[:limits] != nil or card[:band] != nil or card[:gaps?] == true or
        card.stand_ins?

  attr :card, :map, required: true

  defp chart_legend(assigns) do
    assigns =
      assign(assigns,
        items:
          (assigns.card[:series] || []) ++
            if(assigns.card[:limits],
              do: [%{label: assigns.card.limits, color: :neutral, marker: :dashed}],
              else: []
            )
      )

    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1">
      <.legend :if={@items != []} items={@items} />
      <ul class="flex flex-wrap gap-x-4 gap-y-1 text-xs">
        <li :if={@card[:band]} class="flex items-center gap-1.5">
          <span class="chart-key chart-key-band" aria-hidden="true"></span>{@card.band}
        </li>
        <li :if={@card[:gaps?]} class="flex items-center gap-1.5">
          <span class="chart-key chart-key-gap" aria-hidden="true"></span>keine Messung
        </li>
        <li :if={@card.stand_ins?} class="flex items-center gap-1.5">
          <span class="chart-key chart-key-stand-in" aria-hidden="true"></span>Ersatzsensor
        </li>
      </ul>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :latest, :map, required: true
  attr :now, DateTime, required: true
  attr :zone, :string, required: true

  defp sensor_facts(assigns) do
    reading = assigns.room.reading

    assigns =
      assign(assigns,
        sensors:
          for sensor <- [reading.lead | reading.stand_ins] do
            latest = assigns.latest[sensor.id]

            %{
              sensor: sensor,
              role: role(sensor, reading),
              latest: latest,
              status: status_text(sensor, latest, assigns.now, assigns.zone)
            }
          end
      )

    ~H"""
    <section aria-labelledby={"#{@room.id}-sensors"}>
      <.section_heading id={"#{@room.id}-sensors"} level={3}>Sensoren</.section_heading>
      <div class="grid gap-x-8 gap-y-6 md:grid-cols-2">
        <div :for={entry <- @sensors} id={"#{@room.id}-sensor-#{entry.sensor.id}"}>
          <div class="flex flex-wrap items-center gap-2">
            <h4 class="font-semibold">{entry.sensor.name}</h4>
            <.badge style={:plain}>{entry.role}</.badge>
          </div>
          <.description_list class="mt-1">
            <:item label="Letzte Messung">{last_reading(entry.latest, @now, @zone)}</:item>
            <:item :if={entry.sensor.type == :sen66} label="Status">
              <.level_badge_for level={elem(entry.status, 1)} style={:text}>
                {elem(entry.status, 0)}
              </.level_badge_for>
            </:item>
            <:item :if={entry.sensor.type == :sen66} label="Firmware">
              {(entry.latest && entry.latest.firmware_version) || "—"}
            </:item>
            <:item :if={entry.latest && entry.latest.battery_pct} label="Batterie">
              <%= if Sensors.battery_low?(entry.latest) do %>
                <.level_badge_for level={:warn} style={:text}>
                  {number(entry.latest.battery_pct, unit: "%")}
                </.level_badge_for>
              <% else %>
                {number(entry.latest.battery_pct, unit: "%")}
              <% end %>
            </:item>
            <:item label={if entry.sensor.type == :sen66, do: "Seriennummer", else: "Geräte-ID"}>
              <span class="font-mono">{entry.sensor.id}</span>
            </:item>
          </.description_list>
        </div>
      </div>
    </section>
    """
  end

  defp last_reading(nil, _now, _zone), do: "—"

  defp last_reading(%Reading{taken_at: taken_at} = latest, now, zone),
    do: join_meta([since(taken_at, now, zone), age_label(latest, now)])

  # The details stand in the device alert above; here a word.
  defp status_text(sensor, latest, now, zone) do
    case freshness(sensor, latest, now, zone) do
      {:fresh, _age} -> status(sensor, latest)
      {_stale, since} -> {since, :warn}
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
        ink: @verdict_inks[level],
        reason: verdict_reason(verdict, assigns.tile),
        meta:
          co2 &&
            join_meta([co2.source == :stand_in && "Ersatzsensor", age_label(co2, now)])
      )

    ~H"""
    <.card
      id="room_air_tile"
      title="Raumluft"
      subtitle={@tile.name}
      navigate={~p"/sensors" <> "#" <> @tile.id}
      class="h-full"
    >
      <:leading><.plush name="traffic-light" size={:lg} /></:leading>
      <div class="mt-2 flex flex-wrap items-baseline justify-between gap-x-6 gap-y-3">
        <div class="min-w-0" data-verdict data-level={@level}>
          <p class={["text-2xl font-semibold tracking-[-0.02em]", @ink]}>
            {verdict_word(@tile.verdict)}
          </p>
          <p :if={@reason} class="mt-1 text-sm">
            <%= if @level in [:warn, :bad] do %>
              <.level_badge_for level={@level}>{@reason}</.level_badge_for>
            <% else %>
              <span class="text-base-content/70">{@reason}</span>
            <% end %>
          </p>
        </div>
        <div class="text-end" data-co2>
          <p class="text-2xl font-semibold tracking-[-0.02em] tabular-nums whitespace-nowrap">
            {number(@co2 && @co2.value)}
            <span :if={@co2} class="text-base text-base-content/70">ppm</span>
          </p>
          <p class="mt-1 text-sm text-base-content/70">
            CO₂<.meta_sep :if={@meta} />{@meta}
          </p>
        </div>
      </div>
    </.card>
    """
  end
end
