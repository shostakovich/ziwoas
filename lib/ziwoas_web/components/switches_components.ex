defmodule ZiwoasWeb.SwitchesComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  import ZiwoasWeb.ErrorSummary, only: [error_summary: 1]

  alias Ziwoas.Switching.{Row, Schedule}

  @day_abbr [{1, "Mo"}, {2, "Di"}, {3, "Mi"}, {4, "Do"}, {5, "Fr"}, {6, "Sa"}, {7, "So"}]
  @day_names ~w[Montag Dienstag Mittwoch Donnerstag Freitag Samstag Sonntag]
  @source_label %{manual: "manuell", schedule: "Zeitplan"}

  attr :on, :boolean, required: true
  attr :plush, :string, required: true
  attr :label, :string, required: true, doc: "the device's name; `aria-pressed` says the state"
  attr :tone, :atom, default: :plug, values: [:plug, :lamp]
  attr :busy, :boolean, default: false, doc: "its command is still running"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled)
  slot :readout, doc: "a badge on the knob's lower edge, e.g. the power"

  def knob(assigns) do
    ~H"""
    <div class={["sw-knob-wrap", @class]}>
      <button
        type="button"
        class={["sw-knob", @tone == :lamp && "sw-knob-lamp"]}
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
      <div :if={@readout != []} class="sw-knob-readout">{render_slot(@readout)}</div>
    </div>
    """
  end

  attr :row, Row, required: true
  attr :zone, :string, required: true
  attr :pending, :boolean, default: false, doc: "a switch command is running"

  attr :editor, :map,
    default: nil,
    doc: "the open editor: `%{kind: :window | :rule, id: nil | entry id, form: form}`"

  def plug_card(assigns) do
    row = assigns.row
    offline = Row.offline?(row)
    on = Row.on?(row)
    count = Row.rule_count(row)

    assigns =
      assign(assigns,
        plug: row.plug,
        on: on,
        lit: on and not offline,
        offline: offline,
        status: status_line(row, assigns.zone),
        count: if(count > 0, do: count)
      )

    ~H"""
    <.card
      id={"sw_card_#{@plug.id}"}
      data-plug-id={@plug.id}
      as="article"
      class="max-sm:[--card-p:1rem]"
    >
      <div class="flex items-start gap-4" id={"sw_head_#{@plug.id}"}>
        <div class="min-w-0 flex-1 self-center">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <h3 class="card-title">{@plug.name}</h3>
            <.badge :if={@offline} tone={:warning}>Offline</.badge>
          </div>
          <p class="mt-1 text-sm text-base-content/70" data-status>{@status}</p>
        </div>
        <.knob
          on={@lit}
          plush={if @lit, do: "shelly-plug", else: "shelly-plug-off"}
          label={@plug.name}
          disabled={@offline}
          busy={@pending}
          phx-click="switch_plug"
          phx-value-plug_id={@plug.id}
          phx-value-state={if @on, do: "off", else: "on"}
        >
          <:readout :if={@lit}>
            <.badge icon="zap" class="tabular-nums" data-watt>
              {number(@row.watt || 0, unit: "W")}
            </.badge>
          </:readout>
        </.knob>
      </div>
      <.disclosure
        id={"sw_schedule_#{@plug.id}"}
        variant={:button}
        icon="clock"
        summary="Schaltzeiten"
        count={@count}
        class="sm:mt-2"
      >
        <.entries plug={@plug} entries={@row.entries} editor={@editor} />
      </.disclosure>
    </.card>
    """
  end

  attr :plug, :any, required: true
  attr :entries, :list, required: true
  attr :editor, :map, default: nil

  def entries(assigns) do
    ~H"""
    <div id={"sw_rules_#{@plug.id}"}>
      <.list
        :if={@entries != []}
        flush
        class="-mx-[var(--card-p,1.5rem)] border-t border-base-content/10 [&>.list-row]:px-[var(--card-p,1.5rem)]"
      >
        <%= for entry <- @entries do %>
          <.entry_editor :if={editing?(@editor, entry)} plug={@plug} editor={@editor} as="li" />
          <.schedule_entry :if={not editing?(@editor, entry)} entry={entry} plug={@plug} />
        <% end %>
      </.list>
      <div id={"sw_editor_#{@plug.id}"}>
        <.entry_editor :if={@editor && is_nil(@editor.id)} plug={@plug} editor={@editor} />
      </div>
      <div class="-mx-[var(--card-p,1.5rem)] flex flex-wrap gap-2 border-t border-base-content/10 px-[var(--card-p,1.5rem)] pt-4">
        <.button
          id={opener_id(@plug.id, :window)}
          size={:sm}
          icon="plus"
          phx-click="new_entry"
          phx-value-plug_id={@plug.id}
          phx-value-kind="window"
        >
          Zeitfenster
        </.button>
        <.button
          id={opener_id(@plug.id, :rule)}
          size={:sm}
          icon="plus"
          phx-click="new_entry"
          phx-value-plug_id={@plug.id}
          phx-value-kind="rule"
        >
          Einzelschaltung
        </.button>
      </div>
    </div>
    """
  end

  defp editing?(%{id: id}, entry) when not is_nil(id), do: id == to_string(Schedule.id(entry))
  defp editing?(_editor, _entry), do: false

  defp opener_id(plug_id, kind), do: "sw_new_#{kind}_#{plug_id}"

  @doc "Where focus goes once `editor` closes: the row's actions, else the button that opens it."
  @spec focus_return(String.t(), map) :: [String.t()]
  def focus_return(plug_id, %{id: nil, kind: kind}), do: [opener_id(plug_id, kind)]

  def focus_return(plug_id, %{id: id}) do
    row = entry_dom_id(plug_id, id)
    ["#{row}_edit", "#{row}-menu-toggle", opener_id(plug_id, :window)]
  end

  attr :plug, :any, required: true
  attr :editor, :map, required: true
  attr :as, :string, default: "div"

  def entry_editor(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@as}
      id={entry_dom_id(@plug.id, @editor.id || "new")}
      class={[
        "py-4",
        if(@as == "li",
          do: "border-b border-base-content/10 px-[var(--card-p,1.5rem)] last:border-b-0",
          else: "-mx-[var(--card-p,1.5rem)] border-t border-base-content/10 px-[var(--card-p,1.5rem)]"
        )
      ]}
    >
      <.window_form :if={@editor.kind == :window} plug={@plug} form={@editor.form} key={@editor.id} />
      <.single_form :if={@editor.kind == :rule} plug={@plug} form={@editor.form} key={@editor.id} />
    </.dynamic_tag>
    """
  end

  defp entry_dom_id(plug_id, id), do: "sw_entry_#{plug_id}_#{id}"

  attr :entry, :any, required: true
  attr :plug, :any, required: true

  def schedule_entry(assigns) do
    entry = assigns.entry
    window = Schedule.window?(entry)
    id = to_string(Schedule.id(entry))
    enabled = Schedule.enabled?(entry)
    target = %{plug_id: assigns.plug.id, kind: if(window, do: "window", else: "rule"), id: id}

    assigns =
      assign(assigns,
        dom_id: entry_dom_id(assigns.plug.id, id),
        enabled: enabled,
        meta:
          if(window,
            do: "Zeitfenster",
            else: join_meta(["Einzelschaltung", direction(entry.rule.action)])
          ),
        noun: if(window, do: "Zeitfenster", else: "Schaltzeit"),
        toggle: JS.push("set_enabled", value: Map.put(target, :enabled, to_string(not enabled))),
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

  attr :plug, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :key, :string, default: nil, doc: "the group id of a stored Zeitfenster"

  def window_form(assigns) do
    assigns = assign(assigns, :prefix, editor_prefix(assigns.plug.id, assigns.key))

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
      <input type="hidden" name="plug_id" value={@plug.id} />
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
      <.editor_actions plug={@plug} />
    </.form>
    """
  end

  attr :plug, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :key, :string, default: nil, doc: "the id of a stored Einzelschaltung"

  def single_form(assigns) do
    assigns = assign(assigns, :prefix, editor_prefix(assigns.plug.id, assigns.key))

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
      <input type="hidden" name="plug_id" value={@plug.id} />
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
      <.editor_actions plug={@plug} />
    </.form>
    """
  end

  @spec editor_prefix(String.t(), String.t() | nil) :: String.t()
  def editor_prefix(plug_id, key), do: "sw_#{plug_id}_#{key || "new"}"

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

  attr :plug, :any, required: true

  defp editor_actions(assigns) do
    ~H"""
    <.action_bar>
      <.button phx-click="close_editor" phx-value-plug_id={@plug.id}>Abbrechen</.button>
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

  defp offline_line(%Row{last_seen_ts: nil}), do: "Noch keine Statusmeldung"
  defp offline_line(row), do: "Keine Statusmeldung seit #{round(Row.age(row) / 60)} min"

  defp since(time, now, zone) do
    day = local_date(time, zone)

    case Date.diff(local_date(now, zone), day) do
      0 -> clock(time, zone)
      1 -> "gestern #{clock(time, zone)}"
      _days -> "#{day_month(day)} #{clock(time, zone)}"
    end
  end

  defp upcoming(time, now, zone) do
    day = local_date(time, zone)

    case Date.diff(day, local_date(now, zone)) do
      0 -> "um #{clock(time, zone)}"
      1 -> "morgen um #{clock(time, zone)}"
      _days -> "#{Enum.at(@day_names, Date.day_of_week(day) - 1)} um #{clock(time, zone)}"
    end
  end

  defp local_date(time, zone), do: time |> DateTime.shift_zone!(zone) |> DateTime.to_date()

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
