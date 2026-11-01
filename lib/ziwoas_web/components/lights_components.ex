defmodule ZiwoasWeb.LightsComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  import ZiwoasWeb.ErrorSummary, only: [error_summary: 1]
  import ZiwoasWeb.SwitchesComponents, only: [knob: 1]

  alias Ziwoas.Lights
  alias Ziwoas.Lights.Snapshot

  @swatches [
    {"#ff4d4d", "Rot"},
    {"#ff7a3d", "Orange"},
    {"#ffd43b", "Gelb"},
    {"#43d97f", "Grün"},
    {"#22b8cf", "Türkis"},
    {"#4d7cff", "Blau"},
    {"#7c5cff", "Violett"},
    {"#ff6bd6", "Pink"}
  ]
  @swatch_colors Enum.map(@swatches, &elem(&1, 0))
  @preset_max_k 5400

  @plush_types %{
    "H60B0" => "lamp-uplighter",
    "H607C" => "lamp-floor",
    "H6038" => "lamp-sconce",
    "H60A6" => "lamp-ceiling",
    "LGT001" => "lamp-bedside",
    "LLC001" => "lamp-cone",
    "LLC020" => "lamp-bowl"
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

  @zone_columns %{1 => "grid-cols-1", 2 => "grid-cols-2"}

  @hue_effects %{
    "no_effect" => "Kein Effekt",
    "candle" => "Kerze",
    "fire" => "Kaminfeuer",
    "prism" => "Prisma",
    "sparkle" => "Funkeln",
    "opal" => "Opal",
    "glisten" => "Glitzern",
    "underwater" => "Unterwasser",
    "cosmos" => "Kosmos",
    "sunbeam" => "Sonnenstrahl",
    "enchant" => "Zauber"
  }

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
    {~r/autumn|herbst|\bfall\b/u, ["hsl(25 80% 50%)", "hsl(45 85% 52%)"]},
    {~r/\Ano_effect\z/u, ["hsl(45 35% 92%)", "hsl(40 25% 78%)"]}
  ]

  attr :snapshot, Snapshot, required: true
  attr :now, DateTime, required: true, doc: "what a starting lamp counts its seconds against"
  attr :pending, :boolean, default: false, doc: "a command for the lamp is running"

  def light_card(assigns) do
    snapshot = assigns.snapshot
    starting = Lights.starting?(snapshot)
    on = Lights.on?(snapshot) and not starting

    assigns =
      assign(assigns,
        light: snapshot.light,
        lit: Lights.lit?(snapshot),
        starting: starting,
        summary: card_summary(snapshot, assigns.now),
        brightness: on && Lights.brightness(snapshot),
        color: on && not Lights.white?(snapshot) && color_hex(snapshot)
      )

    ~H"""
    <.card
      id={"light_card_#{@light.key}"}
      data-light-key={@light.key}
      as="article"
      class="has-[a:focus-visible]:outline-2 has-[a:focus-visible]:outline-offset-2 has-[a:focus-visible]:outline-primary"
    >
      <div class="flex items-start gap-4">
        <div class="min-w-0 flex-1 self-center">
          <h3 class="card-title block">
            <.link
              navigate={~p"/lights/#{@light.key}"}
              class="after:absolute after:inset-0 focus-visible:outline-none"
            >
              {@light.name}
            </.link><.icon
              name="chevron-right"
              class="ms-1 inline-block align-[-0.125em] text-base-content/70"
            />
          </h3>
          <p
            :for={{line, index} <- Enum.with_index(@summary)}
            class="mt-1 flex items-center gap-2 text-sm text-base-content/70"
            data-status
          >
            <span
              :if={@starting and index == 0}
              class="loading loading-spinner loading-xs motion-reduce:hidden"
              aria-hidden="true"
            ></span>
            {line}
          </p>
        </div>
        <.knob
          tone={:lamp}
          on={@lit}
          plush={plush_name(@light, @lit)}
          label={@light.name}
          busy={@pending}
          class="z-10"
          {command(@light.key, "turn", on: not @lit)}
        >
          <:readout :if={@brightness}>
            <.badge style={:plain} class="tabular-nums" data-brightness>
              <span
                class={["ld-swatch-dot", !@color && "ld-swatch-dot-white"]}
                style={@color && "background-color: #{@color}"}
                aria-hidden="true"
              ></span>{number(@brightness, unit: "%")}
            </.badge>
          </:readout>
        </.knob>
      </div>
    </.card>
    """
  end

  defp plush_name(light, on) do
    name = Map.get(@plush_types, String.upcase(light.sku || ""), "lamp")
    if on, do: name, else: name <> "-off"
  end

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

  defp card_summary(snapshot, now) do
    if Lights.starting?(snapshot),
      do: [
        "Startet … #{Lights.starting_for_s(snapshot, now)} s",
        "Steckdose an, warte auf Lampe"
      ],
      else: [summary(snapshot)]
  end

  defp summary(snapshot) do
    cond do
      Lights.unpowered?(snapshot) -> join_meta(["Aus", "stromlos"])
      not Lights.on?(snapshot) -> "Aus"
      Lights.white?(snapshot) -> join_meta(["An", "Weiß"])
      true -> join_meta(["An", "Farbe"])
    end
  end

  attr :snapshot, Snapshot, required: true

  def power(assigns) do
    snapshot = assigns.snapshot
    zones = Lights.zones(snapshot)

    assigns =
      assign(assigns,
        light: snapshot.light,
        on: Lights.lit?(snapshot),
        unpowered: Lights.unpowered?(snapshot) and not Lights.starting?(snapshot),
        zone_lamp: Lights.zone_lamp?(snapshot),
        zones: zones,
        columns: Map.get(@zone_columns, length(zones), "grid-cols-3")
      )

    ~H"""
    <div id="light_power" class="flex flex-col gap-6">
      <div class="flex items-center gap-4 sm:gap-6">
        <span class="sw-knob sw-knob-lamp sw-knob-hero" data-on={to_string(@on)} aria-hidden="true">
          <.plush name={plush_name(@light, @on)} size={:xxl} class="sw-knob-plush" />
        </span>
        <div class="flex min-w-0 flex-1 flex-col gap-2">
          <.segmented
            mode={:button}
            id="light_power_switch"
            label="Lampe"
            value={to_string(@on)}
            block
            phx-click="turn"
            options={[{"An", "true"}, {"Aus", "false"}]}
          />
          <p :if={@unpowered} class="text-sm text-base-content/70" data-status>
            {join_meta(["Aus", "stromlos"])}
          </p>
        </div>
      </div>
      <div
        :if={@zone_lamp}
        id="light_zones"
        role="group"
        aria-labelledby="light_zones_label"
        hidden={not @on}
      >
        <p id="light_zones_label" class="mb-2 text-sm font-medium">Zonen</p>
        <div class={["grid gap-2", @columns]}>
          <.zone :for={zone <- @zones} zone={zone} light_key={@light.key} />
        </div>
      </div>
    </div>
    """
  end

  attr :snapshot, Snapshot, required: true
  attr :class, :any, default: nil

  def starting_notice(assigns) do
    ~H"""
    <.alert :if={Lights.starting?(@snapshot)} id="light_starting" tone={:info} busy class={@class}>
      Lampe startet — Einstellungen werden übernommen, sobald sie erreichbar ist.
    </.alert>
    """
  end

  attr :zone, Lights.Zone, required: true
  attr :light_key, :string, required: true

  def zone(assigns) do
    ~H"""
    <button
      type="button"
      id={"zone_#{@zone.key}"}
      class="btn ld-zone min-w-0 px-3"
      aria-pressed={to_string(@zone.on)}
      {command(@light_key, "zone", zone: @zone.key, on: not @zone.on)}
    >
      <.icon name={if @zone.on, do: "circle-check", else: "circle"} class="shrink-0" />
      <span class="truncate">{zone_label(@zone.key)}</span>
    </button>
    """
  end

  defp zone_label(key), do: Map.fetch!(@zone_labels, key)

  attr :brightness, :integer, required: true
  attr :on, :boolean, required: true, doc: "lit; off or unpowered keeps the level, inactive"
  attr :revert, :integer, default: nil, doc: "set anew to put a focused thumb back"

  def brightness_panel(assigns) do
    ~H"""
    <form id="light_brightness_form" phx-change="light_command" phx-auto-recover="ignore">
      <.section_heading id="light_brightness_label">
        Helligkeit
        <:actions>
          <output for="light_brightness" class="text-sm tabular-nums">
            {number(@brightness, unit: "%")}
          </output>
        </:actions>
      </.section_heading>
      <input type="hidden" name="command" value="brightness" />
      <div class="flex items-center gap-3">
        <.icon name="sun-dim" class="size-5 shrink-0 text-base-content/70" />
        <input
          class="range ld-range ld-brightness"
          type="range"
          id="light_brightness"
          name="value"
          min="1"
          max="100"
          value={@brightness}
          data-on={to_string(@on)}
          aria-labelledby="light_brightness_label"
          phx-patch-focused={@revert}
          phx-debounce="250"
        />
        <.icon name="sun" class="size-5 shrink-0 text-base-content/70" />
      </div>
    </form>
    """
  end

  attr :panels, :list, required: true, doc: "`[{label, value}]`"
  attr :active, :string, required: true
  slot :inner_block, required: true

  def light_panels(assigns) do
    ~H"""
    <section aria-labelledby="light_panels_label">
      <.section_heading id="light_panels_label">
        Licht
        <:actions>
          <.segmented
            mode={:button}
            id="light_panel_switch"
            label="Lichtart"
            value={@active}
            size={:sm}
            phx-click="show_panel"
            options={@panels}
          />
        </:actions>
      </.section_heading>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :light, :map, required: true
  attr :kelvin, :integer, default: nil, doc: "the colour temperature last set, nil for none"
  attr :revert, :integer, default: nil, doc: "set anew to put a focused thumb back"
  attr :hidden, :boolean, default: false

  def white_panel(assigns) do
    {min_k, max_k} = Lights.color_temp_range(assigns.light)
    presets = presets(min_k, max_k)

    assigns =
      assign(assigns,
        min_k: min_k,
        max_k: max_k,
        slider: assigns.kelvin || min_k,
        presets: presets,
        ticks: for({_label, k} <- presets, do: {k, share(k, min_k, max_k)})
      )

    ~H"""
    <form
      id="light_panel_white"
      data-panel="white"
      aria-label="Weiß"
      class="flex flex-col gap-6"
      hidden={@hidden}
      phx-change="light_command"
      phx-auto-recover="ignore"
    >
      <input type="hidden" name="command" value="color_temp" />
      <div>
        <div class="mb-2 flex items-baseline justify-between gap-2 text-sm">
          <label for="light_temp" class="font-medium">Farbtemperatur</label>
          <output for="light_temp" class="tabular-nums">{number(@slider, unit: "K")}</output>
        </div>
        <input
          class="range ld-range ld-kelvin"
          type="range"
          id="light_temp"
          name="temp_k"
          min={@min_k}
          max={@max_k}
          step="100"
          value={@slider}
          phx-patch-focused={@revert}
          phx-debounce="250"
        />
        <div class="ld-ticks" aria-hidden="true">
          <span :for={{_k, at} <- @ticks} class="ld-tick" style={"--at: #{at}"}></span>
        </div>
        <div class="ld-tick-labels mt-1 flex justify-between gap-2 text-xs text-base-content/70 tabular-nums">
          <span class="flex flex-col">{number(@min_k, unit: "K")}<span>warm</span></span>
          <span
            :for={{k, at} <- Enum.filter(@ticks, &labelled_tick?/1)}
            class="ld-tick-label"
            style={"--at: #{at}"}
            data-tick
          >
            {number(k, unit: "K")}
          </span>
          <span class="flex flex-col text-end">{number(@max_k, unit: "K")}<span>kalt</span></span>
        </div>
      </div>
      <.segmented
        mode={:button}
        id="light_presets"
        label="Voreinstellungen"
        value={@kelvin}
        block
        phx-click="color_temp_preset"
        options={@presets}
      />
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

  # Nearer an end, a label would run into the end's own label on a phone.
  defp labelled_tick?({_k, at}), do: at > 0.2 and at < 0.8

  attr :color, :string, default: nil, doc: "the colour last set as `#rrggbb`, nil for white"
  attr :revert, :integer, default: nil, doc: "set anew to put a focused swatch back"
  attr :zone_lamp, :boolean, default: false
  attr :hidden, :boolean, default: false

  def color_panel(assigns) do
    assigns =
      assign(assigns,
        swatches: Enum.with_index(@swatches),
        custom: not is_nil(assigns.color) and assigns.color not in @swatch_colors,
        label: if(assigns.zone_lamp, do: "Farbe · Welle + Seite", else: "Farbe")
      )

    ~H"""
    <fieldset id="light_panel_color" data-panel="color" hidden={@hidden}>
      <legend class="mb-3 text-sm font-medium">{@label}</legend>
      <div class="ld-swatches">
        <label
          :for={{{swatch, name}, index} <- @swatches}
          class="ld-swatch"
          style={"--ld-swatch: #{swatch}"}
        >
          <input
            type="radio"
            class="sr-only"
            name="light_color"
            id={"light_color_#{index}"}
            checked={@color == swatch}
            data-color={swatch}
            phx-patch-focused={@revert}
            phx-click="light_command"
            phx-value-command="color"
            {rgb_values(swatch)}
          />
          <span class="sr-only">{name}</span>
        </label>
        <label
          class={["ld-swatch ld-swatch-wheel", @custom && "ld-swatch-custom"]}
          title="Weitere Farbe"
          data-light="wheel"
          data-custom={@custom && @color}
          style={@custom && "--ld-custom: #{@color}"}
        >
          <input
            type="color"
            id="light_color_wheel"
            aria-label="Weitere Farbe"
            phx-hook="LightDetail"
            value={@color || "#ff7a3d"}
          />
        </label>
      </div>
    </fieldset>
    """
  end

  defp rgb_values("#" <> hex) do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex

    for {name, byte} <- [r: r, g: g, b: b],
        do: {:"phx-value-#{name}", Integer.to_string(String.to_integer(byte, 16))}
  end

  @spec hex(%{r: 0..255, g: 0..255, b: 0..255}) :: String.t()
  def hex(%{r: r, g: g, b: b}), do: rgb_hex({r, g, b})

  attr :light, :map, required: true
  attr :hidden, :boolean, default: false

  def scenes(assigns) do
    assigns =
      assign(assigns,
        scenes: Lights.scenes(assigns.light),
        kind: scenes_kind(assigns.light),
        vendor: vendor_name(assigns.light)
      )

    ~H"""
    <div id="light_panel_scenes" data-panel="scenes" hidden={@hidden}>
      <%= if @scenes != [] do %>
        <p id="light_scenes_label" class="mb-3 text-sm font-medium">{@vendor}-{@kind}</p>
        <.list class="ld-scenes" aria-labelledby="light_scenes_label">
          <.list_row
            :for={scene <- @scenes}
            title={scene_label(@light, scene)}
            on_click={JS.push("light_command", value: %{command: "effect", effect: scene})}
          >
            <:leading>
              <span class="ld-scene-preview" style={"background-image: #{scene_gradient(scene)}"}></span>
            </:leading>
          </.list_row>
        </.list>
      <% else %>
        <.empty_state title={"Keine #{@kind}"}>
          Diese Lampe meldet keine {@vendor}-{@kind}.
        </.empty_state>
      <% end %>
    </div>
    """
  end

  @doc "What a lamp's vendor calls the presets that take the place of Govee's scenes."
  @spec scenes_kind(Ziwoas.Lights.Light.t()) :: String.t()
  def scenes_kind(%{vendor: :hue}), do: "Effekte"
  def scenes_kind(_light), do: "Szenen"

  defp vendor_name(%{vendor: :hue}), do: "Hue"
  defp vendor_name(_light), do: "Govee"

  defp scene_label(%{vendor: :hue}, effect),
    do:
      Map.get_lazy(@hue_effects, effect, fn ->
        effect |> String.replace("_", " ") |> String.capitalize()
      end)

  defp scene_label(_light, scene), do: scene

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

  def toast(assigns) do
    ~H"""
    <div class="ld-toast-region" role="status" aria-live="polite">
      <div
        :if={@message}
        id="light_toast"
        class="ld-toast flex items-center gap-3 rounded-box border border-base-content/10 bg-popover py-2 ps-4 pe-2 text-sm shadow-lg"
      >
        <span class="min-w-0 flex-1">{@message}</span>
        <.button
          size={:sm}
          variant={:ghost}
          icon="undo-2"
          class="shrink-0"
          {command(@undo.light_key, "zone_undo", victim: @undo.victim, added: @undo.added)}
        >
          Rückgängig
        </.button>
        <.button
          size={:sm}
          variant={:ghost}
          icon="x"
          icon_only
          label="Schließen"
          class="shrink-0"
          phx-click="hide_toast"
        />
      </div>
    </div>
    """
  end

  def toast_assigns(_light, :clear), do: %{message: nil, undo: nil}

  def toast_assigns(light, %{evicted: evicted, added: added}) do
    max = Lights.max_active_zones(light)

    %{
      message: "#{zone_label(evicted)} ausgeschaltet · max. #{max} Zonen",
      undo: %{light_key: light.key, victim: evicted, added: added}
    }
  end

  defp command(key, command, params) do
    values = for {name, value} <- params, do: {:"phx-value-#{name}", to_string(value)}

    [
      "phx-click": "light_command",
      "phx-value-light_key": key,
      "phx-value-command": command
    ] ++ values
  end

  attr :form, Phoenix.HTML.Form, default: nil, doc: "kept after closing, so the exit shows it"
  attr :open, :boolean, required: true
  attr :plugs, :list, required: true

  def settings_sheet(assigns) do
    ~H"""
    <.modal
      id="light_settings"
      title="Einstellungen"
      show={@open}
      on_cancel={JS.push("close_settings")}
    >
      <.light_form :if={@form} form={@form} plugs={@plugs} />
    </.modal>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :plugs, :list, required: true

  def light_form(assigns) do
    assigns = assign(assigns, :options, Enum.map(assigns.plugs, &{&1.name, &1.id}))

    ~H"""
    <.form
      for={@form}
      id="light_form"
      phx-hook="Setzkasten.Components.Forms.FocusInvalid"
      phx-change="validate_settings"
      phx-submit="save_settings"
    >
      <.error_summary id="light_form_errors" form={@form} class="mb-2" />
      <.input field={@form[:name]} label="Name" />
      <.input
        field={@form[:shelly_plug_id]}
        type="select"
        label="Steckdose"
        options={@options}
        prompt="Keine"
        help="Die Steckdose, an der die Lampe hängt. Ist sie aus, wird sie für den nächsten Befehl eingeschaltet."
      />
      <.action_bar>
        <.button id="light_settings_cancel" phx-click={hide_modal("light_settings")}>
          Abbrechen
        </.button>
        <.button type="submit" variant={:primary} phx-disable-with="Speichert …">Speichern</.button>
      </.action_bar>
    </.form>
    """
  end
end
