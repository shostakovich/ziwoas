defmodule ZiwoasWeb.EconomicsLive do
  @moduledoc """
  The Wirtschaftlichkeit page: the overview card, the Kostenposten and the
  Strompreise with their forms. Editing is deliberately absent: with a handful
  of rows, deleting and re-entering is shorter than a form that has to
  remember its row.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.EconomicsComponents

  alias Ziwoas.{Clock, Config, Economics}
  alias Ziwoas.Economics.{CostItem, ElectricityPrice, Overview}

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
    changeset = Economics.change_cost_item(%CostItem{}, params)
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
        {:noreply, socket |> clear_flash() |> assign(cost_form: to_form(changeset))}
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
    changeset = Economics.change_price(%ElectricityPrice{}, params)
    {:noreply, assign(socket, price_form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_price", %{"electricity_price" => params}, socket) do
    case Economics.create_price(params) do
      {:ok, price} ->
        {:noreply,
         socket
         |> put_flash(:info, "Preis ab #{day(price.valid_from)} erfasst")
         |> load()
         |> reset_price_form()}

      {:error, changeset} ->
        {:noreply, socket |> clear_flash() |> assign(price_form: to_form(changeset))}
    end
  end

  def handle_event("delete_price", %{"id" => id}, socket) do
    socket =
      case Economics.delete_price(id) do
        {:ok, price} -> put_flash(socket, :info, "Preis ab #{day(price.valid_from)} gelöscht")
        {:error, _} -> put_flash(socket, :error, "Preis nicht gefunden")
      end

    {:noreply, load(socket)}
  end

  # Each load reads the day afresh: a page left open past midnight moves on.
  defp load(socket) do
    today = today()

    assign(socket,
      today: today,
      overview: Overview.build(today),
      cost_items: Economics.cost_items(),
      prices: Economics.prices()
    )
  end

  defp reset_cost_form(socket) do
    item = %CostItem{spent_on: socket.assigns.today}
    assign(socket, cost_form: to_form(Economics.change_cost_item(item)))
  end

  defp reset_price_form(socket) do
    price = %ElectricityPrice{valid_from: Date.to_iso8601(socket.assigns.today)}
    assign(socket, price_form: to_form(Economics.change_price(price)))
  end

  defp today, do: Clock.today(Config.get().location.timezone)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path}>
      <.header>Wirtschaftlichkeit</.header>

      <.overview_card result={@overview} title="Stand" link={false} />

      <.card title="Kostenposten">
        <p class="small text-body-secondary">
          Alles, was die Anlage gekostet hat. Eine Förderung oder Rückerstattung wird
          als negativer Betrag erfasst.
        </p>

        <%= if @cost_items != [] do %>
          <ul class="list-group list-group-flush mb-2" id="cost_items">
            <li
              :for={item <- @cost_items}
              id={"cost_item-#{item.id}"}
              class="list-group-item economics-row d-flex align-items-center gap-3 px-0"
            >
              <div class="me-auto">
                <div>{item.label}</div>
                <div class="small text-body-secondary tabular-nums">
                  {day(item.spent_on)}
                  <%= if item.note do %>
                    · {item.note}
                  <% end %>
                </div>
              </div>
              <span class="fw-semibold tabular-nums text-nowrap">
                {eur(item.amount_eur)}
              </span>
              <button
                type="button"
                class="btn-close"
                title="Löschen"
                aria-label={"#{item.label} löschen"}
                phx-click="delete_cost_item"
                phx-value-id={item.id}
                data-confirm={"#{item.label} wirklich löschen?"}
              ></button>
            </li>
          </ul>
          <p class="d-flex justify-content-between">
            Summe
            <strong class="tabular-nums">
              {eur(@overview.acquisition_cost_eur)}
            </strong>
          </p>
        <% else %>
          <p class="small text-body-secondary">Noch keine Kostenposten erfasst.</p>
        <% end %>

        <.form
          for={@cost_form}
          id="cost_item_form"
          class="row g-2"
          phx-change="validate_cost_item"
          phx-submit="save_cost_item"
        >
          <.input
            field={@cost_form[:label]}
            label="Bezeichnung"
            wrapper_class="col-12 col-md-6"
          />
          <.input
            field={@cost_form[:amount_eur]}
            label="Betrag in €"
            inputmode="decimal"
            wrapper_class="col-6 col-md-3"
          />
          <.input
            field={@cost_form[:spent_on]}
            type="date"
            label="Datum"
            wrapper_class="col-6 col-md-3"
          />
          <.input field={@cost_form[:note]} label="Notiz (optional)" wrapper_class="col-12" />
          <div class="col-12">
            <.button type="submit" phx-disable-with="Speichert …">Hinzufügen</.button>
          </div>
        </.form>
      </.card>

      <.card title="Strompreise">
        <p class="small text-body-secondary">
          Was eine Kilowattstunde aus dem Netz kostet. Ein Preis gilt ab seinem Datum
          bis zum nächsten; der früheste deckt auch alle Tage davor.
        </p>

        <%= if @prices != [] do %>
          <ul class="list-group list-group-flush mb-3" id="prices">
            <li
              :for={price <- @prices}
              id={"price-#{price.id}"}
              class="list-group-item economics-row d-flex align-items-center gap-3 px-0"
            >
              <span class="me-auto tabular-nums">ab {day(price.valid_from)}</span>
              <span class="fw-semibold tabular-nums text-nowrap">
                {number(price.eur_per_kwh, precision: 4, unit: "€/kWh")}
              </span>
              <button
                type="button"
                class="btn-close"
                title="Löschen"
                aria-label={"Preis ab #{day(price.valid_from)} löschen"}
                phx-click="delete_price"
                phx-value-id={price.id}
                data-confirm={"Preis ab #{day(price.valid_from)} wirklich löschen?"}
              ></button>
            </li>
          </ul>
        <% else %>
          <p class="small text-body-secondary">
            Noch kein Strompreis erfasst. Ohne ihn bleibt die Ersparnis unbekannt.
          </p>
        <% end %>

        <.form
          for={@price_form}
          id="price_form"
          class="row g-2 align-items-end"
          phx-change="validate_price"
          phx-submit="save_price"
        >
          <.input
            field={@price_form[:eur_per_kwh]}
            label="Preis in €/kWh"
            inputmode="decimal"
            wrapper_class="col-6 col-md-4"
          />
          <.input
            field={@price_form[:valid_from]}
            type="date"
            label="Gültig ab"
            wrapper_class="col-6 col-md-4"
          />
          <div class="col-12 col-md-4">
            <.button type="submit" phx-disable-with="Speichert …">Hinzufügen</.button>
          </div>
        </.form>
      </.card>

      <.button variant="outline-secondary" navigate={~p"/solakon"}>Zurück zu PV</.button>
    </Layouts.app>
    """
  end

  defp day(%Date{} = day), do: date(day)
  defp day(iso) when is_binary(iso), do: iso |> Date.from_iso8601!() |> date()
end
