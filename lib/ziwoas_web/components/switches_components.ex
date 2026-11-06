defmodule ZiwoasWeb.SwitchesComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  import ZiwoasWeb.ErrorSummary, only: [error_summary: 1]

  alias Ziwoas.{Heating, LocalDay}
  alias Ziwoas.Heating.Heater
  alias Ziwoas.Switching.{Row, Schedule}

  @day_abbr [{1, "Mo"}, {2, "Di"}, {3, "Mi"}, {4, "Do"}, {5, "Fr"}, {6, "Sa"}, {7, "So"}]
  @day_names ~w[Montag Dienstag Mittwoch Donnerstag Freitag Samstag Sonntag]
  @source_label %{manual: "manuell", schedule: "Zeitplan"}

  attr :on, :boolean, required: true
  attr :plush, :string, required: true
  attr :label, :string, required: true, doc: "the device's name; `aria-pressed` says the state"
  attr :tone, :atom, default: :plug, values: [:plug, :lamp, :heater]
  attr :busy, :boolean, default: false, doc: "its command is still running"
  attr :rest, :global, include: ~w(disabled)

  def knob(assigns) do
    ~H"""
    <div class="sw-knob-wrap">
      <button
        type="button"
        class={["sw-knob", @tone == :lamp && "sw-knob-lamp", @tone == :heater && "sw-knob-heater"]}
        aria-label={@label}
        aria-pressed={to_string(@on)}
        aria-busy={@busy && "true"}
        {@rest}
      >
        <.plush name={@plush} class="sw-knob-plush" />
        <span :if={@busy} class="sw-knob-pending" aria-hidden="true">
          <span class="loading loading-spinner loading-xs motion-reduce:hidden"></span>
          <.icon name="ellipsis" class="size-4 motion-safe:hidden" />
        </span>
      </button>
    </div>
    """
  end

  attr :row, Row, required: true
  attr :zone, :string, required: true
  attr :pending, :boolean, default: false, doc: "a switch command is running"

  @doc "A plug on Schalten: the knob switches it, the name opens its page."
  def plug_tile(assigns) do
    row = assigns.row
    offline = Row.offline?(row)
    on = Row.on?(row)

    assigns =
      assign(assigns,
        plug: row.plug,
        on: on,
        lit: Row.lit?(row),
        offline: offline,
        status: tile_status(row, assigns.zone)
      )

    ~H"""
    <article
      id={"sw_card_#{@plug.id}"}
      data-plug-id={@plug.id}
      class="sw-tile"
      data-lit={@lit && "plug"}
    >
      <div class="sw-tile-top">
        <.knob
          on={@lit}
          plush={if @lit, do: "shelly-plug", else: "shelly-plug-off"}
          label={@plug.name}
          disabled={@offline}
          busy={@pending}
          phx-click="switch_plug"
          phx-value-plug_id={@plug.id}
          phx-value-state={if @on, do: "off", else: "on"}
        />
        <.badge :if={@offline} tone={:warning}>Offline</.badge>
        <.badge :if={@lit} icon="zap" class="tabular-nums" data-watt>
          {number(@row.watt || 0, unit: "W")}
        </.badge>
      </div>
      <.tile_title navigate={~p"/switches/plugs/#{@plug.id}"}>{@plug.name}</.tile_title>
      <p class="sw-tile-status" data-status>{@status}</p>
    </article>
    """
  end

  attr :row, Heating.Row, required: true
  attr :zone, :string, required: true
  attr :pending, :boolean, default: false, doc: "a press is running"
  attr :heat_pending, :boolean, default: false, doc: "a new Heiztemperatur is being set"

  @doc "A heater on Schalten, two tiles wide: knob, name, status and the Heiztemperatur."
  def heater_tile(assigns) do
    row = assigns.row
    offline = Heating.Row.offline?(row)
    heating = Heating.Row.heating?(row)

    assigns =
      assign(assigns,
        heater: row.heater,
        key: row.heater.key,
        offline: offline,
        heating: heating,
        set_to_heat: Heating.Row.set_to_heat?(row),
        thermostat: if(offline, do: nil, else: row.thermostat),
        status: heater_status(row, assigns.zone)
      )

    ~H"""
    <article
      id={"sw_heater_#{@key}"}
      data-heater-key={@key}
      class="sw-tile sw-tile-wide"
      data-lit={@heating && "heater"}
    >
      <div class="flex items-center gap-3">
        <.heater_knob
          heater={@heater}
          heating={@heating}
          set_to_heat={@set_to_heat}
          offline={@offline}
          pending={@pending}
        />
        <div class="min-w-0 flex-1">
          <.tile_title navigate={~p"/switches/heaters/#{@key}"}>{@heater.name}</.tile_title>
          <p class="sw-tile-status" data-status>{@status}</p>
        </div>
        <div class="flex shrink-0 flex-col items-end gap-1">
          <.badge :if={@offline} tone={:warning}>Offline</.badge>
          <.badge
            :if={@thermostat && @thermostat.measured_c}
            icon="thermometer"
            class="tabular-nums"
            data-temperature
          >
            {number(@thermostat.measured_c, precision: 1, unit: "°C")}
          </.badge>
          <.battery :if={@thermostat && @thermostat.battery_low} thermostat={@thermostat} />
        </div>
      </div>
      <.heat_stepper
        key={@key}
        heat_c={@heater.heat_c}
        disabled={@heat_pending or @offline}
        class="sw-tile-stepper"
      />
    </article>
    """
  end

  attr :row, Heating.Row, required: true
  attr :zone, :string, required: true
  attr :pending, :boolean, default: false
  attr :heat_pending, :boolean, default: false

  @doc "A heater's state on its own page: knob, status, temperature, battery and Heiztemperatur."
  def heater_body(assigns) do
    row = assigns.row
    offline = Heating.Row.offline?(row)

    assigns =
      assign(assigns,
        heater: row.heater,
        offline: offline,
        heating: Heating.Row.heating?(row),
        set_to_heat: Heating.Row.set_to_heat?(row),
        thermostat: if(offline, do: nil, else: row.thermostat)
      )

    ~H"""
    <div class="flex items-center gap-4">
      <.heater_knob
        heater={@heater}
        heating={@heating}
        set_to_heat={@set_to_heat}
        offline={@offline}
        pending={@pending}
      />
      <div class="min-w-0">
        <p class="text-lg font-semibold" data-status>
          {if @offline, do: "Nicht erreichbar", else: heater_status(@row, @zone)}
        </p>
        <div :if={@thermostat} class="mt-2 flex flex-wrap gap-2">
          <.badge
            :if={@thermostat.measured_c}
            icon="thermometer"
            class="tabular-nums"
            data-temperature
          >
            {number(@thermostat.measured_c, precision: 1, unit: "°C")}
          </.badge>
          <.battery :if={@thermostat.battery_pct} thermostat={@thermostat} />
        </div>
      </div>
    </div>
    <.heat_stepper
      key={@heater.key}
      heat_c={@heater.heat_c}
      disabled={@heat_pending or @offline}
      class="mt-4"
    />
    """
  end

  attr :heater, Heater, required: true
  attr :heating, :boolean, required: true
  attr :set_to_heat, :boolean, required: true
  attr :offline, :boolean, required: true
  attr :pending, :boolean, required: true

  defp heater_knob(assigns) do
    ~H"""
    <.knob
      on={@heating}
      plush={if @heating, do: "heater", else: "heater-off"}
      label={@heater.name}
      tone={:heater}
      disabled={@offline}
      busy={@pending}
      phx-click="switch_heater"
      phx-value-heater_key={@heater.key}
      phx-value-state={if @set_to_heat, do: "frost", else: "heat"}
    />
    """
  end

  attr :navigate, :string, required: true
  slot :inner_block, required: true

  @doc "A tile's name; its link covers the whole tile, so a tap beside the knob opens the page."
  def tile_title(assigns) do
    ~H"""
    <h3 class="sw-tile-title">
      <.link navigate={@navigate} class="sw-tile-link">{render_slot(@inner_block)}</.link><.icon
        name="chevron-right"
        class="ms-0.5 inline-block size-4 align-[-0.125em] text-base-content/70"
      />
    </h3>
    """
  end

  attr :thermostat, :any, required: true

  defp battery(%{thermostat: %{battery_low: true}} = assigns) do
    ~H"""
    <.badge tone={:warning} class="tabular-nums" data-battery>
      Batterie {number(@thermostat.battery_pct, unit: "%")}
    </.badge>
    """
  end

  defp battery(assigns) do
    ~H"""
    <.badge icon="battery" class="tabular-nums" data-battery>
      <span class="sr-only">Batterie</span> {number(@thermostat.battery_pct, unit: "%")}
    </.badge>
    """
  end

  attr :key, :string, required: true
  attr :heat_c, :float, required: true
  attr :disabled, :boolean, default: false
  attr :class, :any, required: true

  defp heat_stepper(assigns) do
    assigns =
      assign(assigns,
        colder: match?({:ok, _}, Heater.step(assigns.heat_c, :down)),
        warmer: match?({:ok, _}, Heater.step(assigns.heat_c, :up))
      )

    ~H"""
    <div class={["flex items-center justify-between gap-2", @class]}>
      <span id={"sw_heat_label_#{@key}"} class="text-sm text-base-content/70">Heiztemperatur</span>
      <div class="flex items-center gap-2" role="group" aria-labelledby={"sw_heat_label_#{@key}"}>
        <.button
          id={"sw_heat_down_#{@key}"}
          size={:sm}
          icon="minus"
          icon_only
          label="Kälter"
          disabled={@disabled or not @colder}
          phx-click="heat_c"
          phx-value-heater_key={@key}
          phx-value-step="down"
        />
        <output class="min-w-18 text-center font-semibold tabular-nums" data-heat-c>
          {number(@heat_c, precision: 1, unit: "°C")}
        </output>
        <.button
          id={"sw_heat_up_#{@key}"}
          size={:sm}
          icon="plus"
          icon_only
          label="Wärmer"
          disabled={@disabled or not @warmer}
          phx-click="heat_c"
          phx-value-heater_key={@key}
          phx-value-step="up"
        />
      </div>
    </div>
    """
  end

  @doc "Why the heater is in its state, and until when: „Heizt auf 21 °C · manuell bis 22:00“."
  @spec heater_status(Heating.Row.t(), String.t()) :: String.t()
  def heater_status(%Heating.Row{decision: decision, heater: heater, now: now}, zone) do
    case decision do
      %{state: :heat, until: nil} ->
        "Heizt auf #{heat_label(heater)}"

      %{state: :heat, cause: :manual, until: until} ->
        "Heizt auf #{heat_label(heater)} · manuell bis #{moment(until, now, zone)}"

      %{state: :heat, until: until} ->
        "Heizt auf #{heat_label(heater)} · bis #{moment(until, now, zone)}"

      %{state: :frost, until: nil} ->
        "Frostschutz"

      %{state: :frost, until: until} ->
        "Frostschutz · heizt ab #{moment(until, now, zone)}"
    end
  end

  defp heat_label(heater) do
    case Heater.heating_c(heater) do
      :max -> "Maximum"
      celsius -> celsius(celsius)
    end
  end

  defp celsius(value) when value == trunc(value), do: number(value, unit: "°C")
  defp celsius(value), do: number(value, precision: 1, unit: "°C")

  defp moment(time, now, zone) do
    day = LocalDay.date(time, zone)

    if day == LocalDay.date(now, zone),
      do: clock(time, zone),
      else: "#{abbr(Date.day_of_week(day))} #{clock(time, zone)}"
  end

  attr :owner, :any, required: true, doc: "`{:plug, id}` or `{:heater, key}`"
  attr :singles, :boolean, default: true, doc: "it offers an Einzelschaltung too"
  attr :entries, :list, required: true
  attr :editor, :map, default: nil

  def entries(assigns) do
    ~H"""
    <div id={"sw_rules_#{owner_id(@owner)}"}>
      <.list :if={@entries != []}>
        <%= for entry <- @entries do %>
          <.entry_editor
            :if={editing?(@editor, entry)}
            owner={@owner}
            editor={@editor}
            as="li"
          />
          <.schedule_entry
            :if={not editing?(@editor, entry)}
            entry={entry}
            owner={@owner}
          />
        <% end %>
      </.list>
      <div id={"sw_editor_#{owner_id(@owner)}"}>
        <.entry_editor
          :if={@editor && is_nil(@editor.id)}
          owner={@owner}
          editor={@editor}
        />
      </div>
      <div class="mt-3 flex flex-wrap gap-2">
        <.button
          id={opener_id(owner_id(@owner), :window)}
          size={:sm}
          icon="plus"
          phx-click="new_entry"
          phx-value-kind="window"
          {owner_value(@owner)}
        >
          Zeitfenster
        </.button>
        <.button
          :if={@singles}
          id={opener_id(owner_id(@owner), :rule)}
          size={:sm}
          icon="plus"
          phx-click="new_entry"
          phx-value-kind="rule"
          {owner_value(@owner)}
        >
          Einzelschaltung
        </.button>
      </div>
    </div>
    """
  end

  defp editing?(%{id: id}, entry) when not is_nil(id), do: id == to_string(Schedule.id(entry))
  defp editing?(_editor, _entry), do: false

  defp owner_id({_kind, id}), do: id

  defp owner_param({:plug, _id}), do: "plug_id"
  defp owner_param({:heater, _key}), do: "heater_key"

  defp owner_value(owner), do: %{"phx-value-#{owner_param(owner)}" => owner_id(owner)}

  defp opener_id(plug_id, kind), do: "sw_new_#{kind}_#{plug_id}"

  @doc "Where focus goes once `editor` closes: the row's actions, else the button that opens it."
  @spec focus_return({atom, String.t()}, map) :: [String.t()]
  def focus_return(owner, %{id: nil, kind: kind}), do: [opener_id(owner_id(owner), kind)]

  def focus_return(owner, %{id: id}) do
    row = entry_dom_id(owner_id(owner), id)
    ["#{row}_edit", "#{row}-menu-toggle", opener_id(owner_id(owner), :window)]
  end

  attr :owner, :any, required: true
  attr :editor, :map, required: true
  attr :as, :string, default: "div"

  def entry_editor(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@as}
      id={entry_dom_id(owner_id(@owner), @editor.id || "new")}
      class={[
        "py-4",
        if(@as == "li",
          do: "border-b border-base-content/10 px-[var(--card-p,1.5rem)] last:border-b-0",
          else: "-mx-[var(--card-p,1.5rem)] border-t border-base-content/10 px-[var(--card-p,1.5rem)]"
        )
      ]}
    >
      <.window_form
        :if={@editor.kind == :window}
        owner={@owner}
        form={@editor.form}
        key={@editor.id}
      />
      <.single_form
        :if={@editor.kind == :rule}
        owner={@owner}
        form={@editor.form}
        key={@editor.id}
      />
    </.dynamic_tag>
    """
  end

  defp entry_dom_id(plug_id, id), do: "sw_entry_#{plug_id}_#{id}"

  attr :entry, :any, required: true
  attr :owner, :any, required: true

  def schedule_entry(assigns) do
    entry = assigns.entry
    window = Schedule.window?(entry)
    id = to_string(Schedule.id(entry))
    enabled = Schedule.enabled?(entry)

    target = %{
      owner_param(assigns.owner) => owner_id(assigns.owner),
      "kind" => if(window, do: "window", else: "rule"),
      "id" => id
    }

    assigns =
      assign(assigns,
        dom_id: entry_dom_id(owner_id(assigns.owner), id),
        enabled: enabled,
        meta:
          if(window,
            do: "Zeitfenster",
            else: join_meta(["Einzelschaltung", direction(entry.rule.action)])
          ),
        noun: if(window, do: "Zeitfenster", else: "Schaltzeit"),
        toggle: JS.push("set_enabled", value: Map.put(target, "enabled", to_string(not enabled))),
        edit: JS.push("edit_entry", value: target),
        delete: JS.push("delete_entry", value: target)
      )

    ~H"""
    <.list_row id={@dom_id} title={entry_label(@entry)} data-enabled={to_string(@enabled)}>
      <:meta>{@meta}</:meta>
      <:trailing :if={not @enabled}>
        <.badge>Pausiert</.badge>
      </:trailing>
      <:action
        id={"#{@dom_id}_toggle"}
        label={if @enabled, do: "Pausieren", else: "Fortsetzen"}
        icon={if @enabled, do: "pause", else: "play"}
        on_click={@toggle}
      />
      <:action id={"#{@dom_id}_edit"} label="Bearbeiten" icon="pencil" on_click={@edit} />
      <:action
        id={"#{@dom_id}_delete"}
        label="Löschen"
        icon="trash-2"
        danger
        confirm={"#{@noun} löschen?"}
        on_click={@delete}
      />
    </.list_row>
    """
  end

  defp direction(:on), do: "schaltet ein"
  defp direction(_action), do: "schaltet aus"

  attr :owner, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :key, :string, default: nil, doc: "the id of a stored Zeitfenster"

  def window_form(assigns) do
    assigns = assign(assigns, :prefix, editor_prefix(assigns.owner, assigns.key))

    ~H"""
    <.form
      for={@form}
      id={"#{@prefix}_form"}
      phx-hook="Setzkasten.Components.Forms.FocusInvalid"
      phx-mounted={JS.focus_first()}
      class="flex flex-col gap-2"
      aria-labelledby={"#{@prefix}_title"}
      phx-change="validate_entry"
      phx-submit="save_entry"
    >
      <p id={"#{@prefix}_title"} class="font-semibold">
        {if @key, do: "Zeitfenster bearbeiten", else: "Neues Zeitfenster"}
      </p>
      <.error_summary id={"#{@prefix}_errors"} form={@form} />
      <input type="hidden" name={owner_param(@owner)} value={owner_id(@owner)} />
      <div class="grid grid-cols-2 gap-4">
        <.input
          field={@form[:on_at_time]}
          id={"#{@prefix}_on_at_time"}
          type="time"
          label="Einschalten um"
          class="tabular-nums"
        />
        <.input
          field={@form[:off_at_time]}
          id={"#{@prefix}_off_at_time"}
          type="time"
          label="Ausschalten um"
          class="tabular-nums"
        />
      </div>
      <.weekdays field={@form[:days]} id={"#{@prefix}_days"} />
      <p class="text-sm text-base-content/70">
        Über Mitternacht? Einfach <span class="whitespace-nowrap">22:00–06:00</span> eintragen.
      </p>
      <.editor_actions owner={@owner} />
    </.form>
    """
  end

  attr :owner, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :key, :string, default: nil, doc: "the id of a stored Einzelschaltung"

  def single_form(assigns) do
    assigns = assign(assigns, :prefix, editor_prefix(assigns.owner, assigns.key))

    ~H"""
    <.form
      for={@form}
      id={"#{@prefix}_form"}
      phx-hook="Setzkasten.Components.Forms.FocusInvalid"
      phx-mounted={JS.focus_first()}
      class="flex flex-col gap-2"
      aria-labelledby={"#{@prefix}_title"}
      phx-change="validate_entry"
      phx-submit="save_entry"
    >
      <p id={"#{@prefix}_title"} class="font-semibold">
        {if @key, do: "Einzelschaltung bearbeiten", else: "Neue Einzelschaltung"}
      </p>
      <.error_summary id={"#{@prefix}_errors"} form={@form} />
      <input type="hidden" name={owner_param(@owner)} value={owner_id(@owner)} />
      <div class="grid grid-cols-2 gap-4">
        <.input
          field={@form[:at_minute_time]}
          id={"#{@prefix}_at_minute_time"}
          type="time"
          label="Uhrzeit"
          class="tabular-nums"
        />
        <.segmented
          mode={:radio}
          id={"#{@prefix}_action"}
          field={@form[:action]}
          label="Richtung"
          block
          options={[{"An", "on"}, {"Aus", "off"}]}
        />
      </div>
      <.weekdays field={@form[:days]} id={"#{@prefix}_days"} />
      <p class="text-sm text-base-content/70">Bleibt aus, bis etwas anderes einschaltet.</p>
      <.editor_actions owner={@owner} />
    </.form>
    """
  end

  defp editor_prefix(owner, key), do: "sw_#{owner_id(owner)}_#{key || "new"}"

  attr :field, Phoenix.HTML.FormField, required: true
  attr :id, :string, required: true

  def weekdays(assigns) do
    assigns =
      assign(assigns,
        options:
          for(
            {{number, abbr}, name} <- Enum.zip(@day_abbr, @day_names),
            do: %{label: abbr, long_label: name, value: number}
          )
      )

    ~H"""
    <.segmented mode={:checkbox} id={@id} field={@field} label="Wochentage" block options={@options} />
    """
  end

  attr :owner, :any, required: true

  defp editor_actions(assigns) do
    ~H"""
    <.action_bar>
      <.button phx-click="close_editor" {owner_value(@owner)}>Abbrechen</.button>
      <.button type="submit" variant={:primary} phx-disable-with="Speichert …">Speichern</.button>
    </.action_bar>
    """
  end

  @spec weekday_label([integer]) :: String.t()
  def weekday_label(days) do
    sorted = Enum.sort(days)

    if sorted == Enum.map(@day_abbr, &elem(&1, 0)) do
      "täglich"
    else
      sorted
      |> Enum.chunk_while([], &chunk_consecutive/2, &close_chunk/1)
      |> Enum.map_join(", ", &days_label/1)
    end
  end

  defp chunk_consecutive(day, [last | _] = chunk) when day == last + 1, do: {:cont, [day | chunk]}
  defp chunk_consecutive(day, []), do: {:cont, [day]}
  defp chunk_consecutive(day, chunk), do: {:cont, Enum.reverse(chunk), [day]}

  defp close_chunk([]), do: {:cont, []}
  defp close_chunk(chunk), do: {:cont, Enum.reverse(chunk), []}

  defp days_label([single]), do: abbr(single)
  defp days_label([first | _] = group), do: "#{abbr(first)}–#{abbr(List.last(group))}"

  defp abbr(day), do: @day_abbr |> List.keyfind(day, 0) |> elem(1)

  def entry_label(entry) do
    times = entry |> Schedule.rules() |> Enum.map_join("–", &hhmm(&1.at_minute))
    "#{weekday_label(Schedule.days(entry))} · #{times}"
  end

  defp hhmm(minute), do: "#{pad(div(minute, 60))}:#{pad(rem(minute, 60))}"
  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  @spec status_line(Row.t(), String.t()) :: String.t()
  def status_line(row, zone) do
    if Row.offline?(row) do
      offline_line(row)
    else
      word = if Row.on?(row), do: "An", else: "Aus"

      first =
        case Row.since(row) do
          nil ->
            word

          {time, nil} ->
            "#{word} seit #{since(time, row.now, zone)}"

          {time, source} ->
            "#{word} seit #{since(time, row.now, zone)} (#{@source_label[source]})"
        end

      join_meta([first, schedule_part(row, zone)])
    end
  end

  @doc "The short status on a tile: „An · schaltet um 23:30 aus“."
  @spec tile_status(Row.t(), String.t()) :: String.t()
  def tile_status(row, zone) do
    cond do
      Row.offline?(row) -> offline_line(row)
      row.next_edge -> join_meta([on_word(row), schedule_part(row, zone)])
      true -> on_word(row)
    end
  end

  defp on_word(row), do: if(Row.on?(row), do: "An", else: "Aus")

  defp offline_line(%Row{last_seen_ts: nil}), do: "Noch keine Statusmeldung"
  defp offline_line(row), do: "Keine Statusmeldung seit #{round(Row.age(row) / 60)} min"

  defp since(time, now, zone) do
    day = LocalDay.date(time, zone)

    case Date.diff(LocalDay.date(now, zone), day) do
      0 -> clock(time, zone)
      1 -> "gestern #{clock(time, zone)}"
      _days -> "#{day_month(day)} #{clock(time, zone)}"
    end
  end

  defp upcoming(time, now, zone) do
    day = LocalDay.date(time, zone)

    case Date.diff(day, LocalDay.date(now, zone)) do
      0 -> "um #{clock(time, zone)}"
      1 -> "morgen um #{clock(time, zone)}"
      _days -> "#{Enum.at(@day_names, Date.day_of_week(day) - 1)} um #{clock(time, zone)}"
    end
  end

  defp schedule_part(%Row{next_edge: nil, entries: entries}, _zone) do
    cond do
      entries == [] -> "kein Zeitplan"
      not Enum.any?(entries, &Schedule.enabled?/1) -> "Zeitplan pausiert"
      true -> nil
    end
  end

  defp schedule_part(%Row{next_edge: edge, now: now}, zone),
    do:
      "schaltet #{upcoming(edge.at, now, zone)} #{if edge.action == :on, do: "ein", else: "aus"}"
end
