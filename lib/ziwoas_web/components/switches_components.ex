defmodule ZiwoasWeb.SwitchesComponents do
  @moduledoc """
  The Schalten page's partials (`app/views/switches/`, `SwitchesHelper`,
  `Switches::ScheduleEntryComponent`): a plug card with its head, the count
  of Schaltzeiten, the entries and the two inline editors. The controllers
  stream the same pieces back after a write.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.CoreComponents

  alias Ziwoas.Switching.{Row, Rule, Schedule, SingleForm, WindowForm}

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
  attr :error, :string, default: nil
  attr :editor, :any, default: nil, doc: "the new-entry editor: `{:window | :rule, form}`"
  attr :editing, :any, default: nil, doc: "an entry edited in place: `{entry id, editor}`"

  def plug_card(assigns) do
    ~H"""
    <div
      class={["card mb-3", Row.offline?(@row) && "opacity-75"]}
      id={"sw_card_#{@row.plug.id}"}
      data-plug-id={@row.plug.id}
    >
      <div class="card-body">
        <.head row={@row} zone={@zone} error={@error} />
        <%!-- The browser owns `open`: a LiveView patch must not fold the list back up. --%>
        <details class="mt-2" phx-mounted={JS.ignore_attributes(["open"])}>
          <.summary row={@row} />
          <.entries plug={@row.plug} entries={@row.entries} editor={@editor} editing={@editing} />
        </details>
      </div>
    </div>
    """
  end

  attr :row, Row, required: true
  attr :zone, :string, required: true
  attr :error, :string, default: nil

  def head(assigns) do
    row = assigns.row
    on = Row.on?(row)

    assigns =
      assigns
      |> assign_new(:error, fn -> nil end)
      |> assign(
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
        <div class="small text-danger-emphasis" id={"sw_error_#{@row.plug.id}"}>{@error}</div>
      </div>
      <div class="d-flex flex-column align-items-center gap-2">
        <.button_to
          action={"/plugs/#{@row.plug.id}/switch?state=#{if @on, do: "off", else: "on"}"}
          form={[
            class: "button_to",
            "phx-submit": "switch_plug",
            "phx-value-plug_id": @row.plug.id,
            "phx-value-state": if(@on, do: "off", else: "on")
          ]}
          class={["btn btn-light btn-icon sw-knob", not @lit && "off"]}
          aria-label={"#{@row.plug.name} #{if @on, do: "ausschalten", else: "einschalten"}"}
          {attr_if(@offline, disabled: "disabled")}
        >
          <img
            alt=""
            class="sw-knob-plush"
            src={~p"/images/#{"switch_plush_#{if @lit, do: "on", else: "off"}.webp"}"}
          />
        </.button_to>
        <span :if={@lit} class="badge border tabular-nums">
          <span class="text-warning me-1" aria-hidden="true">⚡</span>{de_number(@row.watt || 0)} W
        </span>
      </div>
    </div>
    """
  end

  attr :row, Row, required: true

  # A summary must be its details' first child, so the count needs a Turbo target of its own.
  def summary(assigns) do
    ~H"""
    <summary class="small text-body-secondary py-1" id={"sw_count_#{@row.plug.id}"}>
      Schaltzeiten{count(@row)}
    </summary>
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
  attr :editor, :any, default: nil
  attr :editing, :any, default: nil

  # Rails' Turbo fetches the editors as streams; SwitchesLive opens the same ones on
  # the phx-click of the same links (`entry_editor/1`).
  def entries(assigns) do
    # The controllers render it outside a template, without the defaults.
    assigns = assigns |> assign_new(:editor, fn -> nil end) |> assign_new(:editing, fn -> nil end)

    ~H"""
    <div id={"sw_rules_#{@plug.id}"}>
      <%= for entry <- @entries do %>
        <%= if editor = editing(@editing, entry) do %>
          <.entry_editor plug={@plug} editor={editor} />
        <% else %>
          <.schedule_entry entry={entry} plug={@plug} />
        <% end %>
      <% end %>
      <div id={"sw_editor_#{@plug.id}"}>
        <.entry_editor :if={@editor} plug={@plug} editor={@editor} />
      </div>
      <div class="d-flex flex-wrap gap-2 mt-2">
        <a
          class="btn btn-sm btn-pill btn-outline-secondary"
          data-turbo-stream="true"
          href={"/plugs/#{@plug.id}/switch_windows/new"}
          phx-click="new_entry"
          phx-value-plug_id={@plug.id}
          phx-value-kind="window"
        >
          + Zeitfenster
        </a>
        <a
          class="btn btn-sm btn-pill btn-outline-secondary"
          data-turbo-stream="true"
          href={"/plugs/#{@plug.id}/switch_rules/new"}
          phx-click="new_entry"
          phx-value-plug_id={@plug.id}
          phx-value-kind="rule"
        >
          + Einzelschaltung
        </a>
      </div>
    </div>
    """
  end

  defp editing({id, editor}, entry), do: if(id == to_string(Schedule.id(entry)), do: editor)
  defp editing(nil, _entry), do: nil

  attr :plug, :any, required: true
  attr :editor, :any, required: true

  def entry_editor(assigns) do
    ~H"""
    <%= case @editor do %>
      <% {:window, form} -> %>
        <.window_form plug={@plug} form={form} />
      <% {:rule, form} -> %>
        <.single_form plug={@plug} form={form} />
    <% end %>
    """
  end

  attr :entry, :any, required: true
  attr :plug, :any, required: true

  def schedule_entry(assigns) do
    entry = assigns.entry
    window = Schedule.window?(entry)
    enabled = Schedule.enabled?(entry)
    noun = if window, do: "Zeitfenster", else: "Schaltzeit"
    base = "/plugs/#{assigns.plug.id}/#{if window, do: "switch_windows", else: "switch_rules"}/"
    path = base <> to_string(Schedule.id(entry))

    assigns =
      assign(assigns,
        window: window,
        enabled: enabled,
        noun: noun,
        path: path,
        pill_class: pill_class(window, enabled),
        direction: if(window, do: nil, else: direction(entry.rule.action)),
        event: [
          "phx-value-plug_id": assigns.plug.id,
          "phx-value-kind": if(window, do: "window", else: "rule"),
          "phx-value-id": to_string(Schedule.id(entry))
        ]
      )

    ~H"""
    <div
      class="d-flex align-items-center flex-wrap gap-1 py-1 border-top"
      id={"sw_entry_#{@plug.id}_#{Schedule.id(@entry)}"}
    >
      <%!-- Only an Einzelschaltung carries an arrow: a Zeitfenster's two times say both directions. --%>
      <span class={@pill_class}>
        {entry_label(@entry)}
        <span :if={@direction} class="fw-bold ms-1">{@direction}</span>
      </span>
      <.button_to
        action={@path <> "/enabled"}
        method="patch"
        params={[{"enabled", to_string(not @enabled)}]}
        form={[class: "ms-auto", "phx-submit": "set_enabled"] ++ @event}
        class="btn btn-icon btn-sm"
        aria-label={"#{@noun} #{if @enabled, do: "pausieren", else: "aktivieren"}"}
      >
        <.ui_icon name={if @enabled, do: :pause, else: :play} />
      </.button_to>
      <a
        class="btn btn-icon btn-sm"
        data-turbo-stream="true"
        aria-label={"#{@noun} bearbeiten"}
        href={@path <> "/edit"}
        phx-click="edit_entry"
        {@event}
      >
        <.ui_icon name={:edit} />
      </a>
      <.button_to
        action={@path}
        method="delete"
        form={
          [
            "data-turbo-confirm": "#{@noun} wirklich löschen?",
            class: "button_to",
            "phx-submit": "delete_entry"
          ] ++ @event
        }
        class="btn btn-icon btn-sm"
        aria-label={"#{@noun} löschen"}
      >
        <.ui_icon name={:delete} />
      </.button_to>
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

  attr :scope, :string, required: true
  attr :days, :list, required: true
  attr :id_prefix, :string, required: true

  def weekdays(assigns) do
    assigns = assign(assigns, :day_abbr, @day_abbr)

    ~H"""
    <%!-- The blank value goes outside the group, so unticking every day still sends the key. --%>
    <input type="hidden" name={"#{@scope}[days][]"} value="" />
    <div class="btn-group btn-group-sm w-100" role="group" aria-label="Wochentage">
      <%= for {number, label} <- @day_abbr do %>
        <input
          type="checkbox"
          name={"#{@scope}[days][]"}
          id={"#{@id_prefix}_#{number}"}
          value={number}
          class="btn-check"
          autocomplete="off"
          {attr_if(number in @days, checked: "checked")}
        />
        <label class="btn btn-outline-primary px-1" for={"#{@id_prefix}_#{number}"}>{label}</label>
      <% end %>
    </div>
    """
  end

  attr :plug, :any, required: true
  attr :form, WindowForm, required: true

  def window_form(assigns) do
    form = assigns.form
    persisted = WindowForm.persisted?(form)

    assigns =
      assign(assigns,
        persisted: persisted,
        action:
          if(persisted,
            do: "/plugs/#{assigns.plug.id}/switch_windows/#{form.group_id}",
            else: "/plugs/#{assigns.plug.id}/switch_windows"
          ),
        key: form.group_id || "new"
      )

    ~H"""
    <div {attr_if(@persisted, id: "sw_entry_#{@plug.id}_#{@form.group_id}")}>
      <.rails_form
        action={@action}
        method={if @persisted, do: "patch", else: "post"}
        class="bg-body border rounded p-2 p-sm-3 mt-2 vstack gap-3"
        phx-submit="save_entry"
        phx-value-plug_id={@plug.id}
        phx-value-kind="window"
        phx-value-id={@form.group_id}
      >
        <div :if={@form.errors != []} class="small text-danger-emphasis">
          {Enum.join(@form.errors, ", ")}
        </div>
        <div class="input-group input-group-sm">
          <input
            value={@form.on_at_time}
            class="form-control tabular-nums"
            aria-label="Einschalten um"
            type="time"
            name="switch_window[on_at_time]"
            id="switch_window_on_at_time"
          />
          <span class="input-group-text">bis</span>
          <input
            value={@form.off_at_time}
            class="form-control tabular-nums"
            aria-label="Ausschalten um"
            type="time"
            name="switch_window[off_at_time]"
            id="switch_window_off_at_time"
          />
        </div>
        <.weekdays scope="switch_window" days={@form.days} id_prefix={"sw_day_#{@plug.id}_#{@key}"} />
        <div class="d-flex flex-wrap align-items-center gap-2">
          <.submit value="Speichern" class="btn btn-sm btn-primary" />
          <.cancel plug={@plug} />
          <span class="small text-body-secondary">Über Mitternacht? Einfach 22:00–06:00 eintragen.</span>
        </div>
      </.rails_form>
    </div>
    """
  end

  attr :plug, :any, required: true
  attr :form, SingleForm, required: true

  def single_form(assigns) do
    form = assigns.form
    persisted = SingleForm.persisted?(form)
    key = if persisted, do: form.id, else: "new"

    assigns =
      assign(assigns,
        persisted: persisted,
        action:
          if(persisted,
            do: "/plugs/#{assigns.plug.id}/switch_rules/#{form.id}",
            else: "/plugs/#{assigns.plug.id}/switch_rules"
          ),
        id_prefix: "sw_#{assigns.plug.id}_#{key}",
        day_prefix: "sw_day_#{assigns.plug.id}_#{key}"
      )

    ~H"""
    <div {attr_if(@persisted, id: "sw_entry_#{@plug.id}_#{@form.id}")}>
      <.rails_form
        action={@action}
        method={if @persisted, do: "patch", else: "post"}
        class="bg-body border rounded p-2 p-sm-3 mt-2 vstack gap-3"
        phx-submit="save_entry"
        phx-value-plug_id={@plug.id}
        phx-value-kind="rule"
        phx-value-id={@form.id}
      >
        <div :if={@form.errors != []} class="small text-danger-emphasis">
          {Enum.join(@form.errors, ", ")}
        </div>
        <div class="d-flex flex-wrap align-items-center gap-2">
          <input
            value={@form.at_minute_time}
            class="form-control form-control-sm tabular-nums"
            aria-label="Uhrzeit"
            type="time"
            name="switch_rule[at_minute_time]"
            id="switch_rule_at_minute_time"
          />
          <%!-- Radios, not a checkbox: the direction can never end up neither. --%>
          <div class="btn-group btn-group-sm" role="group" aria-label="Richtung">
            <%= for {value, label} <- [{"on", "an"}, {"off", "aus"}] do %>
              <input
                id={"#{@id_prefix}_action_#{value}"}
                class="btn-check"
                autocomplete="off"
                type="radio"
                value={value}
                name="switch_rule[action]"
                {attr_if(@form.action == value, checked: "checked")}
              />
              <label class="btn btn-outline-primary" for={"#{@id_prefix}_action_#{value}"}>
                {label}
              </label>
            <% end %>
          </div>
        </div>
        <.weekdays scope="switch_rule" days={@form.days} id_prefix={@day_prefix} />
        <div class="d-flex flex-wrap align-items-center gap-2">
          <.submit value="Speichern" class="btn btn-sm btn-primary" />
          <.cancel plug={@plug} />
          <span class="small text-body-secondary">Bleibt aus, bis etwas anderes einschaltet.</span>
        </div>
      </.rails_form>
    </div>
    """
  end

  attr :plug, :any, required: true

  defp cancel(assigns) do
    ~H"""
    <a
      class="btn btn-sm btn-outline-secondary"
      href="/switches"
      phx-click="close_editor"
      phx-value-plug_id={@plug.id}
    >Abbrechen</a>
    """
  end

  # --- SwitchesHelper ----------------------------------------------------------

  @doc "`Mo–Fr`, `Mo, Mi, Fr`, `täglich`."
  @spec weekday_label([integer]) :: String.t()
  def weekday_label(days) do
    sorted = Enum.sort(days)

    if sorted == Rule.iso_days() do
      "täglich"
    else
      sorted
      |> Enum.chunk_while(
        [],
        fn day, chunk ->
          case chunk do
            [last | _] when day == last + 1 -> {:cont, [day | chunk]}
            [] -> {:cont, [day]}
            _ -> {:cont, Enum.reverse(chunk), [day]}
          end
        end,
        fn
          [] -> {:cont, []}
          chunk -> {:cont, Enum.reverse(chunk), []}
        end
      )
      |> Enum.map_join(", ", fn
        [single] -> abbr(single)
        [first | _] = group -> "#{abbr(first)}–#{abbr(List.last(group))}"
      end)
    end
  end

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
