defmodule ZiwoasWeb.EconomicsHTML do
  @moduledoc """
  The Wirtschaftlichkeit page (`economics/index.html.erb`): the overview card,
  the Kostenposten and the Strompreise with their forms. A refused form
  re-renders the whole page with its messages, as Rails does.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.CoreComponents
  import ZiwoasWeb.EconomicsComponents

  attr :look, :string, required: true
  attr :current_path, :string, required: true
  attr :overview, :any, required: true
  attr :cost_items, :list, required: true
  attr :prices, :list, required: true
  attr :today, Date, required: true
  attr :cost_errors, :list, default: []
  attr :price_errors, :list, default: []

  def index(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path}>
      <h1 class="h2 mb-3">Wirtschaftlichkeit</h1>

      <.overview_card result={@overview} title="Stand" link={false} />

      <.card title="Kostenposten">
        <p class="small text-body-secondary">
          Alles, was die Anlage gekostet hat. Eine Förderung oder Rückerstattung wird
          als negativer Betrag erfasst.
        </p>

        <%= if @cost_items != [] do %>
          <ul class="list-group list-group-flush mb-2">
            <li
              :for={item <- @cost_items}
              class="list-group-item economics-row d-flex align-items-center gap-3 px-0"
            >
              <div class="me-auto">
                <div>{item.label}</div>
                <div class="small text-body-secondary tabular-nums">
                  {day(item.spent_on)}
                  <%= if present?(item.note) do %>
                    · {item.note}
                  <% end %>
                </div>
              </div>
              <span class="fw-semibold tabular-nums text-nowrap">
                {de_number(item.amount_eur, precision: 2, unit: "€")}
              </span>
              <.button_to
                action={"/solakon/wirtschaftlichkeit/kosten/#{item.id}"}
                method="delete"
                form={["data-turbo-confirm": "#{item.label} wirklich löschen?", class: "button_to"]}
                class="btn-close"
                title="Löschen"
                aria-label={"#{item.label} löschen"}
              />
            </li>
          </ul>
          <p class="d-flex justify-content-between">
            Summe
            <strong class="tabular-nums">
              {de_number(@overview.acquisition_cost_eur, precision: 2, unit: "€")}
            </strong>
          </p>
        <% else %>
          <p class="small text-body-secondary">Noch keine Kostenposten erfasst.</p>
        <% end %>

        <.rails_form action="/solakon/wirtschaftlichkeit/kosten" class="row g-2">
          <div :if={@cost_errors != []} class="col-12">
            <div class="alert alert-danger mb-0" role="alert">{Enum.join(@cost_errors, ", ")}</div>
          </div>
          <div class="col-12 col-md-6">
            <label class="form-label small mb-1" for="cost_item_label">Bezeichnung</label>
            <input class="form-control" type="text" name="cost_item[label]" id="cost_item_label" />
          </div>
          <div class="col-6 col-md-3">
            <label class="form-label small mb-1" for="cost_item_amount_eur">Betrag in €</label>
            <input
              inputmode="decimal"
              class="form-control"
              type="text"
              name="cost_item[amount_eur]"
              id="cost_item_amount_eur"
            />
          </div>
          <div class="col-6 col-md-3">
            <label class="form-label small mb-1" for="cost_item_spent_on">Datum</label>
            <input
              value={Date.to_iso8601(@today)}
              class="form-control"
              type="date"
              name="cost_item[spent_on]"
              id="cost_item_spent_on"
            />
          </div>
          <div class="col-12">
            <label class="form-label small mb-1" for="cost_item_note">Notiz (optional)</label>
            <input class="form-control" type="text" name="cost_item[note]" id="cost_item_note" />
          </div>
          <div class="col-12">
            <.submit value="Hinzufügen" class="btn btn-primary" />
          </div>
        </.rails_form>
      </.card>

      <.card title="Strompreise">
        <p class="small text-body-secondary">
          Was eine Kilowattstunde aus dem Netz kostet. Ein Preis gilt ab seinem Datum
          bis zum nächsten; der früheste deckt auch alle Tage davor.
        </p>

        <%= if @prices != [] do %>
          <ul class="list-group list-group-flush mb-3">
            <li
              :for={price <- @prices}
              class="list-group-item economics-row d-flex align-items-center gap-3 px-0"
            >
              <span class="me-auto tabular-nums">ab {day(price.valid_from)}</span>
              <span class="fw-semibold tabular-nums text-nowrap">
                {de_number(price.eur_per_kwh, precision: 4, unit: "€/kWh")}
              </span>
              <.button_to
                action={"/solakon/wirtschaftlichkeit/preise/#{price.id}"}
                method="delete"
                form={[
                  "data-turbo-confirm": "Preis ab #{day(price.valid_from)} wirklich löschen?",
                  class: "button_to"
                ]}
                class="btn-close"
                title="Löschen"
                aria-label={"Preis ab #{day(price.valid_from)} löschen"}
              />
            </li>
          </ul>
        <% else %>
          <p class="small text-body-secondary">
            Noch kein Strompreis erfasst. Ohne ihn bleibt die Ersparnis unbekannt.
          </p>
        <% end %>

        <.rails_form action="/solakon/wirtschaftlichkeit/preise" class="row g-2 align-items-end">
          <div :if={@price_errors != []} class="col-12">
            <div class="alert alert-danger mb-0" role="alert">{Enum.join(@price_errors, ", ")}</div>
          </div>
          <div class="col-6 col-md-4">
            <label class="form-label small mb-1" for="electricity_price_eur_per_kwh">
              Preis in €/kWh
            </label>
            <input
              inputmode="decimal"
              class="form-control"
              type="text"
              name="electricity_price[eur_per_kwh]"
              id="electricity_price_eur_per_kwh"
            />
          </div>
          <div class="col-6 col-md-4">
            <label class="form-label small mb-1" for="electricity_price_valid_from">Gültig ab</label>
            <input
              value={Date.to_iso8601(@today)}
              class="form-control"
              type="date"
              name="electricity_price[valid_from]"
              id="electricity_price_valid_from"
            />
          </div>
          <div class="col-12 col-md-4">
            <.submit value="Hinzufügen" class="btn btn-primary" />
          </div>
        </.rails_form>
      </.card>

      <a class="btn btn-outline-secondary" href="/solakon">Zurück zu PV</a>
    </Layouts.app>
    """
  end

  defp day(iso), do: iso |> Date.from_iso8601!() |> Calendar.strftime("%d.%m.%Y")

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
