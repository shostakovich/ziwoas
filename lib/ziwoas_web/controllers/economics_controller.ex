defmodule ZiwoasWeb.EconomicsController do
  @moduledoc """
  The Kostenposten and Strompreise behind the Wirtschaftlichkeit card
  (`EconomicsController`, `CostItemsController`, `ElectricityPricesController`).
  Editing is deliberately absent: with a handful of rows, deleting and
  re-entering is shorter than a form that has to remember its row.
  """
  use ZiwoasWeb, :controller

  alias Ziwoas.{Clock, Config, Economics, Form}
  alias Ziwoas.Economics.{Forms, Overview}

  plug ZiwoasWeb.Owned, [task: :economics] when action != :index

  def index(conn, _params), do: render_index(conn, 200, [])

  def create_cost_item(conn, params) do
    today = today()

    changeset =
      Forms.CostItem.changeset(
        permit(params, "cost_item", ~w[label amount_eur spent_on note]),
        today
      )

    if changeset.valid? do
      Economics.create_cost_item!(changeset.changes, today)
      redirect(conn, to: ~p"/solakon/wirtschaftlichkeit")
    else
      render_index(conn, 422, cost_errors: messages(changeset))
    end
  end

  def delete_cost_item(conn, %{"id" => id}) do
    Economics.delete_cost_item(id)
    redirect(conn, to: ~p"/solakon/wirtschaftlichkeit")
  end

  def create_price(conn, params) do
    today = today()

    changeset =
      Forms.ElectricityPrice.changeset(
        permit(params, "electricity_price", ~w[eur_per_kwh valid_from]),
        today
      )

    result =
      if changeset.valid?,
        do: Economics.create_price(changeset.changes, today),
        else: {:error, messages(changeset)}

    case result do
      {:ok, _price} -> redirect(conn, to: ~p"/solakon/wirtschaftlichkeit")
      {:error, errors} -> render_index(conn, 422, price_errors: List.wrap(errors))
    end
  end

  def delete_price(conn, %{"id" => id}) do
    Economics.delete_price(id)
    redirect(conn, to: ~p"/solakon/wirtschaftlichkeit")
  end

  defp render_index(conn, status, errors) do
    today = today()

    conn
    |> put_status(status)
    |> assign(:page_title, "Wirtschaftlichkeit")
    |> render(:index,
      current_path: conn.request_path,
      overview: Overview.build(today),
      cost_items: Economics.cost_items(),
      prices: Economics.prices(),
      today: today,
      cost_errors: Keyword.get(errors, :cost_errors, []),
      price_errors: Keyword.get(errors, :price_errors, [])
    )
  end

  defp messages(changeset), do: changeset |> Form.messages() |> Enum.uniq()

  # `params.fetch(scope, {}).permit(*keys)`: only the given keys, only scalar values.
  defp permit(params, scope, keys) do
    case params[scope] do
      %{} = given ->
        for {key, value} <- given, key in keys, scalar?(value), into: %{}, do: {key, value}

      _ ->
        %{}
    end
  end

  defp scalar?(value), do: is_nil(value) or is_binary(value)

  defp today, do: Clock.today(Config.app_config().location.timezone)
end
