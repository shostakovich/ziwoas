defmodule ZiwoasWeb.SwitchesComponents do
  @moduledoc """
  The Schalten page's pieces: a plug card with its head, the count of
  Schaltzeiten, the entries and the inline editor. The events they send are
  handled by `ZiwoasWeb.SwitchesLive`.
  """
  use ZiwoasWeb, :html

  alias Ziwoas.Switching.{Row, Rule, Schedule}

  @day_abbr [{1, "Mo"}, {2, "Di"}, {3, "Mi"}, {4, "Do"}, {5, "Fr"}, {6, "Sa"}, {7, "So"}]
  @source_label %{"manual" => "manuell", "schedule" => "Zeitplan"}

  # Drawn in the text colour: emoji render as boxes or in their own colours, depending on the device.
  @ui_icons %{
    play: "M5 3.2v9.6a.6.6 0 0 0 .9.5l7.6-4.8a.6.6 0 0 0 0-1L5.9 2.7a.6.6 0 0 0-.9.5z",
    pause: "M4 3h3v10H4zm5 0h3v10H9z",
    edit:
      "M11.1 1.9a1.3 1.3 0 0 1 1.8 0l1.2 1.2a1.3 1.3 0 0 1 0 1.8L6 13l-3.6.9a.4.4 0 0 1-.5-.5L2.8 9.8z",
    delete:
      "M6 1.5h4l.5 1H14V4H2V2.5h3.5zM3.2 5h9.6l-.7 8.6a1.5 1.5 0 0 1-1.5 1.4H5.4a1.5 1.5 0 0 1-1.5-1.4z"
  }

  attr :row, Row, required: true
  attr :zone, :string, required: true

  attr :editor, :map,
    default: nil,
    doc: "the open editor: `%{kind: :window | :rule, id: nil | entry id, form: form}`"

  def plug_card(assigns) do
    ~H"""
    <div
      class={["card mb-3", Row.offline?(@row) && "opacity-75"]}
      id={"sw_card_#{@row.plug.id}"}
      data-plug-id={@row.plug.id}
    >
      <div class="card-body">
        <.head row={@row} zone={@zone} />
        <%!-- The browser owns `open`: a LiveView patch must not fold the list back up. --%>
        <details class="mt-2" phx-mounted={JS.ignore_attributes(["open"])}>
          <.summary row={@row} />
          <.entries plug={@row.plug} entries={@row.entries} editor={@editor} />
        </details>
      </div>
    </div>
    """
  end

  attr :row, Row, required: true
  attr :zone, :string, required: true

  def head(assigns) do
    row = assigns.row
    on = Row.on?(row)

    assigns =
      assign(assigns,
        on: on,
        lit: on and not Row.offline?(row),
        offline: Row.offline?(row),
        status: status_line(row, assigns.zone)
      )

    ~H"""
    <div class="d-flex align-items-start gap-3" id={"sw_head_#{@row.plug.id}"}>
      <div class="flex-grow-1">
        <h3 class="card-title h5 mb-1">{@row.plug.name}</h3>
        <div class="small text-body-secondary">{@status}</div>
      </div>
      <div class="d-flex flex-column align-items-center gap-2">
        <button
          type="button"
          class={["btn btn-light btn-icon sw-knob", not @lit && "off"]}
          aria-label={"#{@row.plug.name} #{if @on, do: "ausschalten", else: "einschalten"}"}
          disabled={@offline}
          phx-click="switch_plug"
          phx-value-plug_id={@row.plug.id}
          phx-value-state={if @on, do: "off", else: "on"}
        >
          <img
            alt=""
            class="sw-knob-plush"
            src={~p"/images/#{"switch_plush_#{if @lit, do: "on", else: "off"}.webp"}"}
          />
        </button>
        <span :if={@lit} class="badge border tabular-nums">
          <span class="text-warning me-1" aria-hidden="true">⚡</span>{de_number(@row.watt || 0)} W
        </span>
      </div>
    </div>
    """
  end

  attr :row, Row, required: true

  def summary(assigns) do
    ~H"""
    <summary class="small text-body-secondary py-1">Schaltzeiten{count(@row)}</summary>
    """
  end

  defp count(row) do
    case Row.rule_count(row) do
      0 -> ""
      count -> " (#{count})"
    end
  end

  attr :plug, :any, required: true
  attr :entries, :list, required: true
  attr :editor, :map, default: nil

  def entries(assigns) do
    ~H"""
    <div id={"sw_rules_#{@plug.id}"}>
      <%= for entry <- @entries do %>
        <%= if editing?(@editor, entry) do %>
          <.entry_editor plug={@plug} editor={@editor} />
        <% else %>
          <.schedule_entry entry={entry} plug={@plug} />
        <% end %>
      <% end %>
      <div id={"sw_editor_#{@plug.id}"}>
        <.entry_editor :if={@editor && is_nil(@editor.id)} plug={@plug} editor={@editor} />
      </div>
      <div class="d-flex flex-wrap gap-2 mt-2">
        <.button
          type="button"
          variant="outline-secondary"
          size="sm"
          class="btn-pill"
          phx-click="new_entry"
          phx-value-plug_id={@plug.id}
          phx-value-kind="window"
        >
          + Zeitfenster
        </.button>
        <.button
          type="button"
          variant="outline-secondary"
          size="sm"
          class="btn-pill"
          phx-click="new_entry"
          phx-value-plug_id={@plug.id}
          phx-value-kind="rule"
        >
          + Einzelschaltung
        </.button>
      </div>
    </div>
    """
  end

  defp editing?(%{id: id}, entry) when not is_nil(id), do: id == to_string(Schedule.id(entry))
  defp editing?(_editor, _entry), do: false

  attr :plug, :any, required: true
  attr :editor, :map, required: true

  def entry_editor(assigns) do
    ~H"""
    <div id={entry_dom_id(@plug, @editor.id || "new")}>
      <.window_form :if={@editor.kind == :window} plug={@plug} form={@editor.form} key={@editor.id} />
      <.single_form :if={@editor.kind == :rule} plug={@plug} form={@editor.form} key={@editor.id} />
    </div>
    """
  end

  defp entry_dom_id(plug, id), do: "sw_entry_#{plug.id}_#{id}"

  attr :entry, :any, required: true
  attr :plug, :any, required: true

  def schedule_entry(assigns) do
    entry = assigns.entry
    window = Schedule.window?(entry)
    enabled = Schedule.enabled?(entry)
    noun = if window, do: "Zeitfenster", else: "Schaltzeit"

    assigns =
      assign(assigns,
        id: to_string(Schedule.id(entry)),
        kind: if(window, do: "window", else: "rule"),
        enabled: enabled,
        noun: noun,
        pill_class: pill_class(window, enabled),
        direction: if(window, do: nil, else: direction(entry.rule.action))
      )

    ~H"""
    <div
      class="d-flex align-items-center flex-wrap gap-1 py-1 border-top"
      id={entry_dom_id(@plug, @id)}
    >
      <%!-- Only an Einzelschaltung carries an arrow: a Zeitfenster's two times say both directions. --%>
      <span class={@pill_class}>
        {entry_label(@entry)}
        <span :if={@direction} class="fw-bold ms-1">{@direction}</span>
      </span>
      <button
        type="button"
        class="btn btn-icon btn-sm ms-auto"
        aria-label={"#{@noun} #{if @enabled, do: "pausieren", else: "aktivieren"}"}
        phx-click="set_enabled"
        phx-value-plug_id={@plug.id}
        phx-value-kind={@kind}
        phx-value-id={@id}
        phx-value-enabled={to_string(not @enabled)}
      >
        <.ui_icon name={if @enabled, do: :pause, else: :play} />
      </button>
      <button
        type="button"
        class="btn btn-icon btn-sm"
        aria-label={"#{@noun} bearbeiten"}
        phx-click="edit_entry"
        phx-value-plug_id={@plug.id}
        phx-value-kind={@kind}
        phx-value-id={@id}
      >
        <.ui_icon name={:edit} />
      </button>
      <button
        type="button"
        class="btn btn-icon btn-sm"
        aria-label={"#{@noun} löschen"}
        data-confirm={"#{@noun} wirklich löschen?"}
        phx-click="delete_entry"
        phx-value-plug_id={@plug.id}
        phx-value-kind={@kind}
        phx-value-id={@id}
      >
        <.ui_icon name={:delete} />
      </button>
    </div>
    """
  end

  # An Einzelschaltung's pill is drawn open: its counter-direction is missing.
  defp pill_class(window, enabled) do
    tone =
      cond do
        not enabled -> "text-body-secondary text-decoration-line-through"
        window -> "bg-primary-subtle text-primary-emphasis"
        true -> "border-primary text-primary-emphasis"
      end

    Enum.join(
      ["badge rounded-pill fw-normal"] ++ if(window, do: [], else: ["border"]) ++ [tone],
      " "
    )
  end

  defp direction("on"), do: "→ an"
  defp direction(_action), do: "→ aus"

  attr :name, :atom, required: true

  def ui_icon(assigns) do
    assigns = assign(assigns, :d, Map.fetch!(@ui_icons, assigns.name))

    ~H"""
    <svg
      viewBox="0 0 16 16"
      width="16"
      height="16"
      fill="currentColor"
      aria-hidden="true"
      focusable="false"
      data-icon={@name}
    ><path d={@d} /></svg>
    """
  end

  # --- The editors -------------------------------------------------------------------

  attr :plug, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :key, :string, default: nil, doc: "the group id of a stored Zeitfenster"

  def window_form(assigns) do
    assigns = assign(assigns, :prefix, "sw_#{assigns.plug.id}_#{assigns.key || "new"}")

    ~H"""
    <.form
      for={@form}
      id={"#{@prefix}_form"}
      class="bg-body border rounded p-2 p-sm-3 mt-2 vstack gap-3"
      phx-change="validate_entry"
      phx-submit="save_entry"
    >
      <input type="hidden" name="plug_id" value={@plug.id} />
      <div class="row g-2">
        <div class="col">
          <.input
            field={@form[:on_at_time]}
            id={"#{@prefix}_on_at_time"}
            type="time"
            label="Einschalten um"
            class="form-control-sm tabular-nums"
            wrapper_class=""
          />
        </div>
        <div class="col">
          <.input
            field={@form[:off_at_time]}
            id={"#{@prefix}_off_at_time"}
            type="time"
            label="Ausschalten um"
            class="form-control-sm tabular-nums"
            wrapper_class=""
          />
        </div>
      </div>
      <.weekdays field={@form[:days]} id_prefix={"#{@prefix}_day"} />
      <.editor_actions plug={@plug} hint="Über Mitternacht? Einfach 22:00–06:00 eintragen." />
    </.form>
    """
  end

  attr :plug, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :key, :string, default: nil, doc: "the id of a stored Einzelschaltung"

  def single_form(assigns) do
    assigns = assign(assigns, :prefix, "sw_#{assigns.plug.id}_#{assigns.key || "new"}")

    ~H"""
    <.form
      for={@form}
      id={"#{@prefix}_form"}
      class="bg-body border rounded p-2 p-sm-3 mt-2 vstack gap-3"
      phx-change="validate_entry"
      phx-submit="save_entry"
    >
      <input type="hidden" name="plug_id" value={@plug.id} />
      <div class="d-flex flex-wrap align-items-end gap-2">
        <.input
          field={@form[:at_minute_time]}
          id={"#{@prefix}_at_minute_time"}
          type="time"
          label="Uhrzeit"
          class="form-control-sm tabular-nums"
          wrapper_class=""
        />
        <.action_choice field={@form[:action]} id_prefix={"#{@prefix}_action"} />
      </div>
      <.weekdays field={@form[:days]} id_prefix={"#{@prefix}_day"} />
      <.editor_actions plug={@plug} hint="Bleibt aus, bis etwas anderes einschaltet." />
    </.form>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :id_prefix, :string, required: true

  # Radios, not a checkbox: the direction can never end up neither.
  defp action_choice(assigns) do
    assigns =
      assign(assigns, value: to_string(assigns.field.value), errors: errors(assigns.field))

    ~H"""
    <div>
      <div class="btn-group btn-group-sm" role="group" aria-label="Richtung">
        <%= for {value, label} <- [{"on", "an"}, {"off", "aus"}] do %>
          <input
            id={"#{@id_prefix}_#{value}"}
            class="btn-check"
            autocomplete="off"
            type="radio"
            value={value}
            name={@field.name}
            checked={@value == value}
          />
          <label class="btn btn-outline-primary" for={"#{@id_prefix}_#{value}"}>{label}</label>
        <% end %>
      </div>
      <.error :for={message <- @errors}>{message}</.error>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :id_prefix, :string, required: true

  def weekdays(assigns) do
    assigns =
      assign(assigns,
        day_abbr: @day_abbr,
        checked: assigns.field.value |> List.wrap() |> Enum.map(&to_string/1),
        errors: errors(assigns.field)
      )

    ~H"""
    <div>
      <%!-- The blank value goes first, so unticking every day still sends the key. --%>
      <input type="hidden" name={@field.name <> "[]"} value="" />
      <div class="btn-group btn-group-sm w-100" role="group" aria-label="Wochentage">
        <%= for {number, label} <- @day_abbr do %>
          <input
            type="checkbox"
            name={@field.name <> "[]"}
            id={"#{@id_prefix}_#{number}"}
            value={number}
            class="btn-check"
            autocomplete="off"
            checked={to_string(number) in @checked}
          />
          <label class="btn btn-outline-primary px-1" for={"#{@id_prefix}_#{number}"}>{label}</label>
        <% end %>
      </div>
      <.error :for={message <- @errors}>{message}</.error>
    </div>
    """
  end

  defp errors(field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &translate_error/1),
      else: []
  end

  attr :plug, :any, required: true
  attr :hint, :string, required: true

  defp editor_actions(assigns) do
    ~H"""
    <div class="d-flex flex-wrap align-items-center gap-2">
      <.button size="sm">Speichern</.button>
      <.button
        type="button"
        variant="outline-secondary"
        size="sm"
        phx-click="close_editor"
        phx-value-plug_id={@plug.id}
      >
        Abbrechen
      </.button>
      <span class="small text-body-secondary">{@hint}</span>
    </div>
    """
  end

  # --- Labels ------------------------------------------------------------------------

  @doc "`Mo–Fr`, `Mo, Mi, Fr`, `täglich`."
  @spec weekday_label([integer]) :: String.t()
  def weekday_label(days) do
    sorted = Enum.sort(days)

    if sorted == Rule.iso_days() do
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

  @doc "A window's days come from its on rule, which reads a shift past midnight back out."
  def entry_label(entry) do
    times = entry |> Schedule.rules() |> Enum.map_join("–", &Rule.at_minute_time/1)
    "#{weekday_label(Schedule.days(entry))} · #{times}"
  end

  @doc "The plug's state, where it came from and what the schedule does next."
  @spec status_line(Row.t(), String.t()) :: String.t()
  def status_line(row, zone) do
    if Row.offline?(row) do
      offline_line(row)
    else
      on = Row.on?(row)
      word = if on, do: "An", else: "Aus"
      command = row.last_command

      first =
        if command && command.action == "on" == on,
          do:
            "#{word} seit #{clock(command.inserted_at, zone)} (#{@source_label[command.source]})",
          else: word

      Enum.join([first, schedule_part(row, zone)], " · ")
    end
  end

  defp offline_line(%Row{last_seen_ts: nil}), do: "Noch keine Statusmeldung"
  defp offline_line(row), do: "Keine Statusmeldung seit #{round(Row.age(row) / 60)} min"

  defp schedule_part(%Row{next_edge: nil}, _zone), do: "kein Zeitplan"

  defp schedule_part(%Row{next_edge: edge}, zone),
    do:
      "nächste Schaltung: #{clock(edge.at, zone)} → #{if edge.action == :on, do: "an", else: "aus"}"

  defp clock(time, zone), do: time |> DateTime.shift_zone!(zone) |> Calendar.strftime("%H:%M")
end
