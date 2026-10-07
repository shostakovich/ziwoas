defmodule ZiwoasWeb.CoreComponents do
  @moduledoc """
  Shared function components in the style of Phoenix 1.8's generator, on
  felt-css (Bootstrap class names) instead of Tailwind. Error messages are
  German without Gettext, see `translate_error/1`.
  """
  use Phoenix.Component

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc "A felt-css card: optional title and subtitle above the content."
  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :class, :any, default: nil
  attr :as, :string, default: "section"
  attr :level, :integer, default: 2
  attr :rest, :global
  slot :inner_block

  def card(assigns) do
    ~H"""
    <.dynamic_tag tag_name={@as} class={["card", "mb-3", @class]} {@rest}>
      <div class="card-body">
        <%= if present?(@title) do %>
          <.dynamic_tag tag_name={"h#{@level}"} class="card-title">{@title}</.dynamic_tag>
          <p :if={present?(@subtitle)} class="card-subtitle">{@subtitle}</p>
        <% end %>
        {render_slot(@inner_block)}
      </div>
    </.dynamic_tag>
    """
  end

  @doc """
  A flash message as a dismissible felt-css alert.

      <.flash kind={:info} flash={@flash} />
  """
  attr :id, :string, doc: "the optional id of the flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"
  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "alert alert-dismissible d-flex align-items-start gap-2 mb-3",
        @kind == :info && "alert-success",
        @kind == :error && "alert-danger"
      ]}
      {@rest}
    >
      <div>
        <strong :if={@title} class="d-block">{@title}</strong>
        {msg}
      </div>
      <button type="button" class="btn-close" aria-label="Schließen"></button>
    </div>
    """
  end

  @doc "The flash messages of a page, plus the notices for a lost connection."
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="Keine Verbindung"
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        Verbindung wird wiederhergestellt …
      </.flash>
      <.flash
        id="server-error"
        kind={:error}
        title="Etwas ist schiefgelaufen"
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Verbindung wird wiederhergestellt …
      </.flash>
    </div>
    """
  end

  @doc """
  A button, or a link styled as one when `href`, `navigate` or `patch` is given.

      <.button>Speichern</.button>
      <.button variant="outline-danger" phx-click="delete" data-confirm="Wirklich löschen?">Löschen</.button>
      <.button navigate={~p"/"}>Zurück</.button>
  """
  attr :variant, :string, default: "primary", doc: "the felt-css button variant (btn-<variant>)"
  attr :size, :string, default: nil, values: [nil, "sm", "lg"]
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form)

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :classes, [
        "btn",
        "btn-#{assigns.variant}",
        assigns.size && "btn-#{assigns.size}",
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button class={@classes} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  @doc """
  A form input with label and German error messages, on a `Phoenix.HTML.FormField`
  or with `name`/`value` given directly.

      <.input field={@form[:label]} label="Bezeichnung" />
      <.input field={@form[:plug_id]} type="select" options={@plugs} prompt="Bitte wählen" />
      <.input field={@form[:enabled]} type="checkbox" label="Aktiv" />

  `type="checkbox"` takes `switch` for a felt-css form switch. Other types
  (`number`, `time`, `date`, `color`, `range`, …) render a plain `<input>`.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :switch, :boolean, default: false, doc: "a checkbox drawn as a switch"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "extra classes for the control"
  attr :wrapper_class, :any, default: "mb-3"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={["form-check", @switch && "form-switch", @wrapper_class]}>
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        role={@switch && "switch"}
        class={["form-check-input", @errors != [] && "is-invalid", @class]}
        {@rest}
      />
      <label :if={@label} class="form-check-label" for={@id}>{@label}</label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <select
        id={@id}
        name={@name}
        class={["form-select", @errors != [] && "is-invalid", @class]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <textarea
        id={@id}
        name={@name}
        class={["form-control", @errors != [] && "is-invalid", @class]}
        {@rest}
      >{Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          if(@type in ~w(range), do: "form-range", else: "form-control"),
          @type == "color" && "form-control-color",
          @errors != [] && "is-invalid",
          @class
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc "A form error message below its control."
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <div class="invalid-feedback d-block">{render_slot(@inner_block)}</div>
    """
  end

  @doc "A page header: title, optional subtitle and actions on the right."
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class="d-flex flex-wrap align-items-center justify-content-between gap-3 mb-3">
      <div>
        <h1 class="mb-1">{render_slot(@inner_block)}</h1>
        <p :if={@subtitle != []} class="text-body-secondary mb-0">{render_slot(@subtitle)}</p>
      </div>
      <div :if={@actions != []} class="d-flex gap-2">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Translates an error tuple from a changeset into German.

  Messages written in German at the validation (`message: "…"`) pass through
  with their bindings filled in; Ecto's standard English messages are looked
  up by their validation.
  """
  @spec translate_error({String.t(), keyword}) :: String.t()
  def translate_error({msg, opts}) do
    opts
    |> Keyword.get(:validation)
    |> german(msg, opts)
    |> interpolate(opts)
  end

  @doc "Translates the errors for a field from a keyword list of errors."
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  defp german(:required, "can't be blank", _opts), do: "muss ausgefüllt werden"
  defp german(:inclusion, "is invalid", _opts), do: "ist kein gültiger Wert"
  defp german(:exclusion, "is reserved", _opts), do: "ist nicht erlaubt"
  defp german(:format, "has invalid format", _opts), do: "hat ein ungültiges Format"
  defp german(:cast, "is invalid", _opts), do: "ist ungültig"
  defp german(:unique, "has already been taken", _opts), do: "ist bereits vergeben"
  defp german(:acceptance, "must be accepted", _opts), do: "muss akzeptiert werden"
  defp german(:confirmation, "does not match" <> _, _opts), do: "stimmt nicht überein"

  defp german(:number, "must be " <> _, opts) do
    case Keyword.get(opts, :kind) do
      :less_than -> "muss kleiner als %{number} sein"
      :greater_than -> "muss größer als %{number} sein"
      :less_than_or_equal_to -> "darf höchstens %{number} sein"
      :greater_than_or_equal_to -> "muss mindestens %{number} sein"
      :equal_to -> "muss %{number} sein"
      :not_equal_to -> "darf nicht %{number} sein"
    end
  end

  defp german(:length, "should be " <> _, opts) do
    case {Keyword.get(opts, :type), Keyword.get(opts, :kind)} do
      {:list, :min} -> "braucht mindestens %{count} Einträge"
      {:list, :max} -> "darf höchstens %{count} Einträge haben"
      {:list, :is} -> "braucht genau %{count} Einträge"
      {_, :min} -> "muss mindestens %{count} Zeichen lang sein"
      {_, :max} -> "darf höchstens %{count} Zeichen lang sein"
      {_, :is} -> "muss genau %{count} Zeichen lang sein"
    end
  end

  defp german(_validation, msg, _opts), do: msg

  defp interpolate(msg, opts) do
    Regex.replace(~r/%{(\w+)}/, msg, fn whole, key -> option_text(opts, key, whole) end)
  end

  defp option_text(opts, key, fallback) do
    case Enum.find(opts, fn {name, _} -> Atom.to_string(name) == key end) do
      {_, value} -> to_string(value)
      nil -> fallback
    end
  end

  @doc "Shows an element with a fade (`phx-*` bindings)."
  def show(js \\ %JS{}, selector) do
    JS.show(js, to: selector, time: 200, transition: {"fade", "opacity-0", "opacity-100"})
  end

  @doc "Hides an element with a fade (`phx-*` bindings)."
  def hide(js \\ %JS{}, selector) do
    JS.hide(js, to: selector, time: 200, transition: {"fade", "opacity-100", "opacity-0"})
  end

  @doc "A number as German UI text, see `Ziwoas.GermanNumber.format/2`."
  def de_number(value, opts \\ []), do: Ziwoas.GermanNumber.format(value, opts)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
