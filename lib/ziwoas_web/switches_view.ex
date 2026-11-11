defmodule ZiwoasWeb.SwitchesView do
  @moduledoc """
  The view Schalten shows (ADR-0017): every room, the resident's favourites, one room, or the
  devices without one. It lives in the address as `?raum=alle|favoriten|ohne|<room id>`, and a
  device's page carries it back as `?von=`.
  """
  use ZiwoasWeb, :verified_routes

  @type t :: :all | :favourites | :none | {:room, pos_integer}

  @doc "The view a parameter names; `nil` for a missing or unknown one."
  @spec parse(term) :: t | nil
  def parse("alle"), do: :all
  def parse("favoriten"), do: :favourites
  def parse("ohne"), do: :none

  def parse(param) when is_binary(param) do
    case Integer.parse(param) do
      {id, ""} when id > 0 -> {:room, id}
      _unknown -> nil
    end
  end

  def parse(_param), do: nil

  @spec to_param(t) :: String.t()
  def to_param(:all), do: "alle"
  def to_param(:favourites), do: "favoriten"
  def to_param(:none), do: "ohne"
  def to_param({:room, id}), do: to_string(id)

  @spec path(t) :: String.t()
  def path(view), do: ~p"/switches?#{[raum: to_param(view)]}"

  @doc "Where a device's page leads back to: the view it was opened from, else Schalten."
  @spec back_path(term) :: String.t()
  def back_path(param) do
    case parse(param) do
      nil -> ~p"/switches"
      view -> path(view)
    end
  end
end
