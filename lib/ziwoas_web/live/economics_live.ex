defmodule ZiwoasWeb.EconomicsLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.EconomicsComponents
  import ZiwoasWeb.ErrorSummary, only: [error_summary: 1]

  alias Ziwoas.{Clock, Config, Economics}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Wirtschaftlichkeit")
     |> load()
     |> reset_cost_form()
     |> reset_price_form()}
  end

  @impl true
  def handle_event("validate_cost_item", %{"cost_item" => params}, socket) do
    changeset = Economics.change_cost_item(params)
    {:noreply, assign(socket, cost_form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_cost_item", %{"cost_item" => params}, socket) do
    case Economics.create_cost_item(params) do
      {:ok, item} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{item.label} erfasst")
         |> load()
         |> reset_cost_form()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> clear_flash()
         |> assign(cost_form: to_form(changeset))}
    end
  end

  def handle_event("delete_cost_item", %{"id" => id}, socket) do
    socket =
      case Economics.delete_cost_item(id) do
        {:ok, item} -> put_flash(socket, :info, "#{item.label} gelöscht")
        {:error, _} -> put_flash(socket, :error, "Kostenposten nicht gefunden")
      end

    {:noreply, load(socket)}
  end

  def handle_event("validate_price", %{"electricity_price" => params}, socket) do
    changeset = Economics.change_price(params)
    {:noreply, assign(socket, price_form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_price", %{"electricity_price" => params}, socket) do
    case Economics.create_price(params) do
      {:ok, price} ->
        {:noreply,
         socket
         |> put_flash(:info, "Preis ab #{date(price.valid_from)} erfasst")
         |> load()
         |> reset_price_form()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> clear_flash()
         |> assign(price_form: to_form(changeset))}
    end
  end

  def handle_event("delete_price", %{"id" => id}, socket) do
    socket =
      case Economics.delete_price(id) do
        {:ok, price} -> put_flash(socket, :info, "Preis ab #{date(price.valid_from)} gelöscht")
        {:error, _} -> put_flash(socket, :error, "Preis nicht gefunden")
      end

    {:noreply, load(socket)}
  end

  # Each load reads the day afresh: a page left open past midnight moves on.
  defp load(socket) do
    today = today()

    assign(socket,
      today: today,
      overview: Economics.overview(today),
      cost_items: Economics.cost_items(),
      prices: Economics.prices()
    )
  end

  defp reset_cost_form(socket),
    do: assign(socket, cost_form: to_form(Economics.new_cost_item(socket.assigns.today)))

  defp reset_price_form(socket),
    do: assign(socket, price_form: to_form(Economics.new_price(socket.assigns.today)))

  defp today, do: Clock.today(Config.get().location.timezone)

  # As stored, up to five places, but never fewer than a euro amount's two.
  defp price_decimals(eur_per_kwh) do
    %Decimal{exp: exp} = Decimal.normalize(eur_per_kwh)
    -exp |> max(2) |> min(5)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path}>
      <.header back={~p"/solakon"} back_label="PV">
        Wirtschaftlichkeit
        <:subtitle :if={since(@overview)}>{since(@overview)}</:subtitle>
      </.header>

      <div class="flex flex-col gap-8">
        <.overview result={@overview} heading={false} />

        <section aria-labelledby="cost-items-heading">
          <.section_heading id="cost-items-heading" count={length(@cost_items)}>
            Kostenposten
          </.section_heading>
          <p class="text-sm text-base-content/70 max-w-prose mb-3">
            Alles, was die Anlage gekostet hat. Eine Förderung oder Rückerstattung wird
            als negativer Betrag erfasst.
          </p>

          <.list :if={@cost_items != []} id="cost_items">
            <.list_row
              :for={item <- @cost_items}
              id={"cost_item-#{item.id}"}
              title={item.label}
              trailing_on_phone={:title}
            >
              <:meta>{join_meta([date(item.spent_on), item.note])}</:meta>
              <:trailing><.amount value={item.amount_eur} /></:trailing>
              <:action
                id={"cost_item-#{item.id}-delete"}
                label="Löschen"
                icon="trash-2"
                danger
                confirm={"„#{item.label}“ löschen?"}
                on_click={JS.push("delete_cost_item", value: %{id: item.id})}
              />
            </.list_row>
            <:foot label="Summe" actions={1}>
              <.euro value={@overview.acquisition_cost_eur} />
            </:foot>
          </.list>
          <.empty_state :if={@cost_items == []} id="cost_items_empty">
            Noch keine Kostenposten erfasst.
          </.empty_state>

          <.form
            for={@cost_form}
            id="cost_item_form"
            phx-hook="Setzkasten.Components.Forms.FocusInvalid"
            class="mt-6"
            phx-change="validate_cost_item"
            phx-submit="save_cost_item"
          >
            <.section_heading level={3} size={:sm}>Kostenposten erfassen</.section_heading>
            <.error_summary id="cost_item_form_errors" form={@cost_form} class="mb-4" />
            <div class="grid gap-4 md:grid-cols-2">
              <.input field={@cost_form[:label]} label="Bezeichnung" required />
              <.input field={@cost_form[:amount_eur]} label="Betrag" suffix="€" numeric required />
              <.input field={@cost_form[:spent_on]} type="date" label="Datum" required />
              <.input field={@cost_form[:note]} label="Notiz (optional)" />
            </div>
            <.action_bar>
              <.button type="submit" variant={:primary} phx-disable-with="Speichert …">
                Hinzufügen
              </.button>
            </.action_bar>
          </.form>
        </section>

        <section aria-labelledby="prices-heading">
          <.section_heading id="prices-heading" count={length(@prices)}>
            Strompreise
          </.section_heading>
          <p class="text-sm text-base-content/70 max-w-prose mb-3">
            Was eine Kilowattstunde aus dem Netz kostet. Ein Preis gilt ab seinem Datum
            bis zum nächsten; der früheste deckt auch alle Tage davor.
          </p>

          <.list :if={@prices != []} id="prices">
            <.list_row
              :for={price <- @prices}
              id={"price-#{price.id}"}
              title={"ab #{date(price.valid_from)}"}
              trailing_on_phone={:title}
            >
              <:trailing>
                <span class="tabular-nums whitespace-nowrap">
                  {number(price.eur_per_kwh,
                    precision: price_decimals(price.eur_per_kwh),
                    unit: "€/kWh"
                  )}
                </span>
              </:trailing>
              <:action
                id={"price-#{price.id}-delete"}
                label="Löschen"
                icon="trash-2"
                danger
                confirm={"Preis ab #{date(price.valid_from)} löschen?"}
                on_click={JS.push("delete_price", value: %{id: price.id})}
              />
            </.list_row>
          </.list>
          <.empty_state :if={@prices == []} id="prices_empty">
            Noch kein Strompreis erfasst. Ohne ihn bleibt die Ersparnis unbekannt.
          </.empty_state>

          <.form
            for={@price_form}
            id="price_form"
            phx-hook="Setzkasten.Components.Forms.FocusInvalid"
            class="mt-6"
            phx-change="validate_price"
            phx-submit="save_price"
          >
            <.section_heading level={3} size={:sm}>Preis erfassen</.section_heading>
            <.error_summary id="price_form_errors" form={@price_form} class="mb-4" />
            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@price_form[:eur_per_kwh]}
                label="Preis"
                suffix="€/kWh"
                numeric
                required
              />
              <.input field={@price_form[:valid_from]} type="date" label="Gültig ab" required />
            </div>
            <.action_bar>
              <.button type="submit" variant={:primary} phx-disable-with="Speichert …">
                Hinzufügen
              </.button>
            </.action_bar>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
