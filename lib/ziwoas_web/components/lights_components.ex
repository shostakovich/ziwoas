defmodule ZiwoasWeb.LightsComponents do
  @moduledoc """
  A lamp on the Schalten page and on its own page: the tile, the power hero
  with its zones, the brightness, white, colour and scene panels, the toast and
  the settings form. The controls send `"light_command"` with `command` and its
  parameters (`ZiwoasWeb.LightEvents`); the tile adds `light_key`.
  """
  use ZiwoasWeb, :html

  alias Ziwoas.Lights
  alias Ziwoas.Lights.Snapshot

  @swatches ~w[#ff4d4d #ff7a3d #ffd43b #43d97f #22b8cf #4d7cff #7c5cff #ff6bd6]
  @preset_max_k 5400

  @plush_types %{
    "H60B0" => "uplighter",
    "H607C" => "floorlamp",
    "H6038" => "sconce",
    "H60A6" => "ceiling"
  }

  @zone_labels %{
    "bottomLightToggle" => "Leselicht",
    "rippleLightToggle" => "Welle",
    "sideLightToggle" => "Seite",
    "baseLightToggle" => "Sockel",
    "pillarLightToggle" => "Säule",
    "leftLightToggle" => "Links",
    "rightLightToggle" => "Rechts",
    "mainLightToggle" => "Hauptlampe",
    "backgroundLightToggle" => "Ring"
  }

  # The bridge only gives scene names, so names that say what they look like get a matching palette.
  @palettes [
    {~r/aurora|nordlicht|northern/u,
     ["hsl(150 70% 45%)", "hsl(175 70% 42%)", "hsl(270 55% 55%)"]},
    {~r/party|disco|rainbow|regenbogen|dance/u,
     [
       "hsl(0 85% 58%)",
       "hsl(48 95% 55%)",
       "hsl(140 65% 45%)",
       "hsl(210 85% 55%)",
       "hsl(285 70% 58%)"
     ]},
    {~r/sunset|sonnenuntergang|dusk|abend/u, ["hsl(32 95% 58%)", "hsl(335 75% 58%)"]},
    {~r/sunrise|sonnenaufgang|dawn|morgen/u, ["hsl(48 95% 65%)", "hsl(18 90% 60%)"]},
    {~r/ocean|\bsea\b|meer|wave|aqua|lagoon|water|wasser/u,
     ["hsl(195 80% 50%)", "hsl(225 70% 40%)"]},
    {~r/forest|wald|jungle|dschungel|spring|frühling|grass/u,
     ["hsl(105 50% 48%)", "hsl(150 55% 30%)"]},
    {~r/candle|kerze|fire|feuer|flame|kamin/u, ["hsl(40 95% 58%)", "hsl(20 90% 45%)"]},
    {~r/romantic|romantik|love|liebe|valentin/u, ["hsl(340 80% 65%)", "hsl(355 75% 45%)"]},
    {~r/reading|lesen|study|work|arbeit|cozy|gemütlich/u, ["hsl(45 90% 88%)", "hsl(36 80% 70%)"]},
    {~r/night|nacht|sleep|schlaf|moon|mond|\bstar(s|ry)?\b|stern/u,
     ["hsl(235 50% 32%)", "hsl(265 45% 48%)"]},
    {~r/snow|schnee|\bice\b|\beis\b|winter|frost/u, ["hsl(195 60% 88%)", "hsl(210 55% 68%)"]},
    {~r/christmas|weihnacht|xmas/u, ["hsl(355 75% 48%)", "hsl(140 55% 35%)"]},
    {~r/autumn|herbst|\bfall\b/u, ["hsl(25 80% 50%)", "hsl(45 85% 52%)"]}
  ]

  # --- The Schalten tile -------------------------------------------------------------

  attr :snapshot, Snapshot, required: true

  def light_card(assigns) do
    snapshot = assigns.snapshot
    on = Lights.on?(snapshot)

    assigns =
      assign(assigns,
        light: snapshot.light,
        on: on,
        summary: summary(snapshot),
        chip:
          on &&
            %{
              swatch: color_hex(snapshot) || "#ffd9a0",
              label: number(Lights.brightness(snapshot), unit: "%")
            }
      )

    ~H"""
    <div class="card mb-3" id={"light_card_#{@light.key}"} data-light-key={@light.key}>
      <div class="card-body d-flex align-items-start gap-3">
        <div class="flex-grow-1">
          <.link
            class="d-block text-reset text-decoration-none"
            aria-label={"#{@light.name} Details"}
            navigate={~p"/lights/#{@light.key}"}
          >
            <h3 class="card-title h5 mb-1">{@light.name}</h3>
            <div class="small text-body-secondary">{@summary}</div>
          </.link>
          <.link
            class="d-inline-block small link-secondary mt-3"
            navigate={~p"/lights/#{@light.key}"}
          >
            Anpassen ›
          </.link>
        </div>

        <div class="d-flex flex-column align-items-center gap-2">
          <button
            type="button"
            class={["btn btn-light btn-icon sw-knob sw-lamp-knob", not @on && "off"]}
            aria-label={"#{@light.name} umschalten"}
            {command(@light.key, "turn", on: not @on)}
          >
            <img alt="" class="sw-knob-plush" src={~p"/images/#{plush_image(@light, @on)}"} />
          </button>

          <span :if={@chip} class="badge border tabular-nums">
            <span class="sw-swatch me-1" style={"background-color: #{@chip.swatch}"}></span>{@chip.label}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp plush_image(light, on) do
    type = Map.get(@plush_types, String.upcase(light.sku || ""), "generic")
    "lamp_#{type}_#{if on, do: "on", else: "off"}.webp"
  end

  @doc "`#rrggbb` of the lamp's colour, nil without one."
  @spec color_hex(Snapshot.t()) :: String.t() | nil
  def color_hex(snapshot) do
    case Lights.rgb(snapshot) do
      nil -> nil
      rgb -> rgb_hex(rgb)
    end
  end

  defp rgb_hex({r, g, b}), do: "#" <> Enum.map_join([r, g, b], &hex_byte/1)

  defp hex_byte(value),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(2, "0")

  defp summary(snapshot) do
    cond do
      not Lights.on?(snapshot) -> "Aus"
      Lights.white?(snapshot) -> "An · Weiß"
      true -> "An · Farbe"
    end
  end

  # --- The hero ------------------------------------------------------------------------

  attr :snapshot, Snapshot, required: true

  def power(assigns) do
    snapshot = assigns.snapshot
    zones = Lights.zones(snapshot)

    assigns =
      assign(assigns,
        light: snapshot.light,
        on: Lights.on?(snapshot),
        zone_lamp: Lights.zone_lamp?(snapshot),
        zones: zones,
        columns: min(length(zones), 3)
      )

    ~H"""
    <div id="light_power" class="card mb-3">
      <div class="card-body">
        <div class="d-flex align-items-center gap-3">
          <span
            class={[
              "btn btn-light btn-icon sw-knob sw-lamp-knob sw-lamp-hero pe-none flex-shrink-0",
              not @on && "off"
            ]}
            aria-hidden="true"
          >
            <img
              width="112"
              height="112"
              alt=""
              class="sw-knob-plush"
              src={~p"/images/#{plush_image(@light, @on)}"}
            />
          </span>
          <div class="btn-group flex-grow-1" role="group" aria-label="Lampe">
            <button
              :for={{label, value} <- [{"An", true}, {"Aus", false}]}
              type="button"
              aria-pressed={to_string(@on == value)}
              class={["btn btn-outline-primary", @on == value && "active"]}
              {command(@light.key, "turn", on: value)}
            >
              {label}
            </button>
          </div>
        </div>
        <div :if={@zone_lamp} class="mt-3" role="group" aria-label="Zonen" hidden={not @on}>
          <p class="mb-2 small text-uppercase text-body-secondary" aria-hidden="true">Zonen</p>
          <div class={"row row-cols-#{@columns} g-2 ld-choices ld-zones"}>
            <.zone :for={zone <- @zones} zone={zone} light_key={@light.key} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :zone, Lights.Zone, required: true
  attr :light_key, :string, required: true

  def zone(assigns) do
    ~H"""
    <div class="col">
      <button
        type="button"
        id={"zone_#{@zone.key}"}
        class={["btn btn-outline-primary w-100 px-2", @zone.on && "active"]}
        aria-pressed={to_string(@zone.on)}
        aria-label={"#{zone_label(@zone.key)} an/aus"}
        {command(@light_key, "zone", zone: @zone.key, on: not @zone.on)}
      >
        {zone_label(@zone.key)}
      </button>
    </div>
    """
  end

  defp zone_label(key), do: Map.fetch!(@zone_labels, key)

  # --- The panels -----------------------------------------------------------------

  attr :brightness, :integer, required: true

  @doc "The brightness slider: a form, so the server hears it debounced."
  def brightness_panel(assigns) do
    assigns = assign(assigns, :fill, share(assigns.brightness, 1, 100) * 100)

    ~H"""
    <form id="light_brightness_form" class="card mb-3" phx-change="light_command">
      <div class="card-body">
        <input type="hidden" name="command" value="brightness" />
        <div class="d-flex gap-1 mb-2 small text-uppercase text-body-secondary">
          <label for="light_brightness">Helligkeit</label><span aria-hidden="true">·</span>
          <output for="light_brightness" class="text-body tabular-nums">
            {number(@brightness, unit: "%")}
          </output>
        </div>
        <input
          class="form-range ld-range"
          type="range"
          id="light_brightness"
          name="value"
          min="1"
          max="100"
          value={@brightness}
          style={"--felt-form-range-fill: #{@fill}%"}
          phx-debounce="250"
        />
      </div>
    </form>
    """
  end

  attr :tabs, :list, required: true, doc: "`[{key, label}]`"
  attr :active, :string, required: true

  def tabs(assigns) do
    ~H"""
    <div class="nav nav-pills nav-fill mb-3" role="tablist" aria-label="Lichtart">
      <button
        :for={{key, label} <- @tabs}
        type="button"
        class={["nav-link", @active == key && "active"]}
        role="tab"
        id={"light_tab_#{key}"}
        aria-controls={"light_panel_#{key}"}
        aria-selected={to_string(@active == key)}
        data-tab={key}
        phx-click="select_tab"
        phx-value-tab={key}
      >
        {label}
      </button>
    </div>
    """
  end

  attr :light, :map, required: true
  attr :kelvin, :integer, default: nil, doc: "the colour temperature last set, nil for none"
  attr :hidden, :boolean, default: false

  def white_panel(assigns) do
    {min_k, max_k} = Lights.color_temp_range(assigns.light)

    assigns =
      assign(assigns,
        min_k: min_k,
        max_k: max_k,
        slider: assigns.kelvin || min_k,
        presets: presets(min_k, max_k)
      )

    ~H"""
    <form
      class="card mb-3"
      id="light_panel_white"
      role="tabpanel"
      aria-labelledby="light_tab_white"
      data-tab="white"
      hidden={@hidden}
      phx-change="light_command"
    >
      <div class="card-body">
        <input type="hidden" name="command" value="color_temp" />
        <div class="d-flex gap-1 mb-2 small text-uppercase text-body-secondary">
          <label for="light_temp">Lichtfarbe</label><span aria-hidden="true">·</span>
          <output for="light_temp" class="text-body tabular-nums">
            {number(@slider, unit: "K")}
          </output>
        </div>
        <input
          class="form-range ld-range ld-white"
          type="range"
          id="light_temp"
          name="temp_k"
          min={@min_k}
          max={@max_k}
          step="100"
          value={@slider}
          phx-debounce="250"
        />
        <div class="ld-ticks" aria-hidden="true">
          <span
            :for={{_label, preset} <- @presets}
            class="ld-tick"
            style={"--at: #{share(preset, @min_k, @max_k)}"}
          ></span>
        </div>
        <div class="d-flex justify-content-between small text-body-secondary mt-1">
          <span>{number(@min_k, unit: "K")} · warm</span>
          <span>{number(@max_k, unit: "K")} · kalt</span>
        </div>
        <div class="d-flex gap-2 mt-3 ld-choices">
          <button
            :for={{label, preset} <- @presets}
            type="button"
            class={["btn btn-sm btn-outline-primary flex-fill", @kelvin == preset && "active"]}
            aria-pressed={to_string(@kelvin == preset)}
            data-temp={preset}
            phx-click="light_command"
            phx-value-command="color_temp"
            phx-value-temp_k={preset}
          >
            {label}
          </button>
        </div>
      </div>
    </form>
    """
  end

  # Clamped into the lamp's range, or a preset would land where the active button doesn't show.
  defp presets(min_k, max_k) do
    high = @preset_max_k |> max(min_k) |> min(max_k)

    [
      {"Gemütlich", min_k},
      {"Neutral", round((min_k + high) / 2.0 / 100) * 100},
      {"Arbeiten", high}
    ]
  end

  defp share(value, min, max) do
    span = max - min
    if span > 0, do: Float.round((value - min) / span, 4), else: 0
  end

  attr :color, :string, default: nil, doc: "the colour last set as `#rrggbb`, nil for white"
  attr :zone_lamp, :boolean, default: false
  attr :hidden, :boolean, default: false

  @doc """
  The swatches are radios that send their colour; the wheel is the
  `LightDetail` hook, which sends what the native picker chose, debounced.
  """
  def color_panel(assigns) do
    custom = not is_nil(assigns.color) and assigns.color not in @swatches

    assigns =
      assign(assigns,
        swatches: Enum.with_index(@swatches),
        custom: custom,
        label: if(assigns.zone_lamp, do: "Farbe · Welle + Seite", else: "Farbe")
      )

    ~H"""
    <div
      class="card mb-3"
      id="light_panel_color"
      role="tabpanel"
      aria-labelledby="light_tab_color"
      data-tab="color"
      hidden={@hidden}
    >
      <div class="card-body">
        <p class="d-block mb-2 small text-uppercase text-body-secondary" id="light_color_label">
          {@label}
        </p>
        <div class="ld-swatches" role="radiogroup" aria-labelledby="light_color_label">
          <%= for {swatch, index} <- @swatches do %>
            <input
              type="radio"
              class="btn-check"
              name="light_color"
              id={"light_color_#{index}"}
              autocomplete="off"
              checked={@color == swatch}
              data-color={swatch}
              phx-click="light_command"
              phx-value-command="color"
              {rgb_values(swatch)}
            />
            <label
              class="btn btn-icon border ld-swatch"
              for={"light_color_#{index}"}
              style={"background-color: #{swatch}"}
            >
              <span class="visually-hidden">Farbe {swatch}</span>
            </label>
          <% end %>
          <label
            class={["btn btn-icon border ld-swatch ld-swatch-wheel", @custom && "ld-swatch-custom"]}
            title="Weitere Farbe"
            data-light="wheel"
            style={@custom && "--ld-custom: #{@color}"}
          >
            <span class="visually-hidden">Weitere Farbe</span>
            <input
              type="color"
              id="light_color_wheel"
              phx-hook="LightDetail"
              value={@color || "#ff7a3d"}
            />
          </label>
        </div>
      </div>
    </div>
    """
  end

  defp rgb_values("#" <> hex) do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex

    for {name, byte} <- [r: r, g: g, b: b],
        do: {:"phx-value-#{name}", Integer.to_string(String.to_integer(byte, 16))}
  end

  @doc "`#rrggbb` of a colour command's `%{r:, g:, b:}`."
  @spec hex(%{r: 0..255, g: 0..255, b: 0..255}) :: String.t()
  def hex(%{r: r, g: g, b: b}), do: rgb_hex({r, g, b})

  attr :light, :map, required: true
  attr :hidden, :boolean, default: false

  def scenes(assigns) do
    assigns = assign(assigns, :scenes, Lights.scenes(assigns.light))

    ~H"""
    <div
      class="card mb-3"
      id="light_panel_scenes"
      role="tabpanel"
      aria-labelledby="light_tab_scenes"
      data-tab="scenes"
      hidden={@hidden}
    >
      <div class="card-body">
        <%= if @scenes != [] do %>
          <p class="d-block mb-2 small text-uppercase text-body-secondary">Govee-Szenen</p>
          <div class="ld-scenes">
            <div class="row row-cols-2 row-cols-sm-3 g-2">
              <div :for={scene <- @scenes} class="col">
                <button
                  type="button"
                  class="btn btn-light d-flex flex-column align-items-stretch w-100 p-0 overflow-hidden"
                  {command(@light.key, "effect", effect: scene)}
                >
                  <span class="ld-scene-preview" style={"background-image: #{scene_gradient(scene)}"}></span>
                  <span class="small text-start text-truncate px-2 py-1">{scene}</span>
                </button>
              </div>
            </div>
          </div>
        <% else %>
          <p class="d-block mb-2 small text-uppercase text-body-secondary">Szenen</p>
          <p class="small text-body-secondary mb-0">Diese Lampe meldet keine Govee-Szenen.</p>
        <% end %>
      </div>
    </div>
    """
  end

  defp scene_gradient(name),
    do: "linear-gradient(135deg, #{Enum.join(scene_colours(name), ", ")})"

  defp scene_colours(name) do
    key = String.downcase(name)

    Enum.find_value(@palettes, hashed_colours(key), fn {pattern, colours} ->
      if Regex.match?(pattern, key), do: colours
    end)
  end

  defp hashed_colours(key) do
    sum = key |> String.to_charlist() |> Enum.sum()
    ["hsl(#{rem(sum, 360)} 70% 55%)", "hsl(#{rem(sum * 7, 360)} 65% 45%)"]
  end

  attr :message, :string, default: nil
  attr :undo, :map, default: nil, doc: "`%{light_key:, victim:, added:}`"

  # Stays .show: visibility is the hidden attribute's job (LightLive hides it after 5 s).
  def toast(assigns) do
    ~H"""
    <div
      id="light_toast"
      class="toast show"
      role="status"
      aria-live="polite"
      hidden={is_nil(@message)}
    >
      <div :if={@message} class="toast-body d-flex align-items-center gap-2">
        <span>{@message}</span>
        <button
          type="button"
          class="btn btn-sm btn-link fw-bold ms-auto"
          {command(@undo.light_key, "zone_undo", victim: @undo.victim, added: @undo.added)}
        >
          Rückgängig
        </button>
      </div>
    </div>
    """
  end

  @doc "The toast after a zone change: an eviction or nothing."
  def toast_assigns(_light, :clear), do: %{message: nil, undo: nil}

  def toast_assigns(light, %{evicted: evicted, added: added}) do
    max = Lights.max_active_zones(light)

    %{
      message: "#{zone_label(evicted)} ausgeschaltet · max. #{max} Zonen",
      undo: %{light_key: light.key, victim: evicted, added: added}
    }
  end

  # A lamp control: the "light_command" event with the command's parameters.
  defp command(key, command, params) do
    values = for {name, value} <- params, do: {:"phx-value-#{name}", to_string(value)}

    [
      "phx-click": "light_command",
      "phx-value-light_key": key,
      "phx-value-command": command
    ] ++ values
  end

  # --- Settings -------------------------------------------------------------------------

  attr :form, Phoenix.HTML.Form, required: true
  attr :plugs, :list, required: true

  @doc """
  The settings as a modal sheet, the `SettingsSheet` hook: it opens the dialog
  (the browser owns `open`, so a patch from `validate_settings` keeps it open),
  closes it on the backdrop and on `data-dismiss="dialog"`, and tells the
  LiveView when it closed (`"close_settings"`).
  """
  def settings_sheet(assigns) do
    ~H"""
    <dialog
      class="modal"
      closedby="any"
      aria-labelledby="light_settings_title"
      id="light_settings_dialog"
      phx-hook="SettingsSheet"
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <div class="modal-dialog modal-dialog-centered">
        <div class="modal-content">
          <div class="modal-header">
            <h1 class="modal-title fs-5" id="light_settings_title">Einstellungen</h1>
            <button
              type="button"
              class="btn-close"
              aria-label="Schließen"
              data-dismiss="dialog"
            ></button>
          </div>
          <div class="modal-body">
            <.light_form form={@form} plugs={@plugs} />
          </div>
        </div>
      </div>
    </dialog>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :plugs, :list, required: true

  def light_form(assigns) do
    assigns = assign(assigns, :options, Enum.map(assigns.plugs, &{&1.name, &1.id}))

    ~H"""
    <.form for={@form} id="light_form" phx-change="validate_settings" phx-submit="save_settings">
      <.input field={@form[:name]} label="Name" />
      <.input
        field={@form[:shelly_plug_id]}
        type="select"
        label="Shelly-Plug"
        options={@options}
        prompt="— keine —"
        wrapper_class="mb-4"
      />
      <div class="d-flex justify-content-end gap-2">
        <.button type="button" variant="outline-secondary" data-dismiss="dialog">Abbrechen</.button>
        <.button>Speichern</.button>
      </div>
    </.form>
    """
  end
end
