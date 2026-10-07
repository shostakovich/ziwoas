defmodule ZiwoasWeb.CoreComponents do
  @moduledoc """
  Shared function components, ported from the Rails ViewComponents of the
  same name (`app/components/`). Markup and classes stay identical: the golden
  master compares them after normalisation.
  """
  use Phoenix.Component

  @doc "A felt-css card (`CardComponent`): optional title and subtitle above the content."
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
  Rails' `button_to`: a form with one button, `_method` for any verb but POST,
  the CSRF token, then `params` as hidden fields in key order. `form` are the
  form's own attributes (Rails' `form_class`/`form:`).
  """
  attr :action, :string, required: true
  attr :method, :string, default: "post"
  attr :params, :list, default: []
  attr :form, :list, default: [class: "button_to"]
  attr :rest, :global, include: ~w(disabled)
  slot :inner_block

  def button_to(assigns) do
    assigns = update(assigns, :params, &Enum.sort_by(&1, fn {name, _} -> to_string(name) end))

    ~H"""
    <form method="post" action={@action} {@form}>
      <input :if={@method != "post"} type="hidden" name="_method" value={@method} />
      <button type="submit" {@rest}>{render_slot(@inner_block)}</button>
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input :for={{name, value} <- @params} type="hidden" name={name} value={value} />
    </form>
    """
  end

  @doc "Rails' `form_with`: a POST form with the CSRF token and `_method` for any other verb."
  attr :action, :string, required: true
  attr :method, :string, default: "post"
  attr :rest, :global
  slot :inner_block

  def rails_form(assigns) do
    ~H"""
    <form action={@action} accept-charset="UTF-8" method="post" {@rest}>
      <input :if={@method != "post"} type="hidden" name="_method" value={@method} />
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      {render_slot(@inner_block)}
    </form>
    """
  end

  @doc "Rails' `f.submit`."
  attr :value, :string, required: true
  attr :class, :string, required: true

  def submit(assigns) do
    ~H"""
    <input type="submit" name="commit" value={@value} class={@class} data-disable-with={@value} />
    """
  end

  @doc "A number as German UI text (`de_number`), see `Ziwoas.GermanNumber.format/2`."
  def de_number(value, opts \\ []), do: Ziwoas.GermanNumber.format(value, opts)

  @doc ~S'Optional attributes as a list: HEEx renders `attr={false}` as `attr=""`.'
  def attr_if(true, attrs), do: attrs
  def attr_if(_condition, _attrs), do: []

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
