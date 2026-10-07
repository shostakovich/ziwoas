defmodule Ziwoas.Plugs.Roster do
  @moduledoc """
  The configured plugs plus their roles: the one place that knows who
  produces and who consumes, and which sign a measurement carries.
  """
  alias Ziwoas.Plugs.Plug

  @enforce_keys [:all, :by_id]
  defstruct [:all, :by_id]

  @type t :: %__MODULE__{all: [Plug.t()], by_id: %{String.t() => Plug.t()}}

  @bucket_key_by_role %{producer: :production_w, consumer: :consumption_w}

  @spec new(t | [Plug.t()]) :: t
  def new(%__MODULE__{} = roster), do: roster
  def new(plugs), do: %__MODULE__{all: plugs, by_id: Map.new(plugs, &{&1.id, &1})}

  @spec ids(t) :: [String.t()]
  def ids(%__MODULE__{all: all}), do: Enum.map(all, & &1.id)

  @spec consumers(t) :: [Plug.t()]
  def consumers(roster), do: with_role(roster, :consumer)

  @spec producers(t) :: [Plug.t()]
  def producers(roster), do: with_role(roster, :producer)

  @spec consumer_ids(t) :: [String.t()]
  def consumer_ids(roster), do: roster |> consumers() |> Enum.map(& &1.id)

  @spec producer_ids(t) :: [String.t()]
  def producer_ids(roster), do: roster |> producers() |> Enum.map(& &1.id)

  defp with_role(%__MODULE__{all: all}, role), do: Enum.filter(all, &(&1.role == role))

  @spec find(t, String.t()) :: Plug.t() | nil
  def find(%__MODULE__{by_id: by_id}, plug_id), do: Map.get(by_id, plug_id)

  @spec role_of(t, String.t()) :: Plug.role() | nil
  def role_of(roster, plug_id) do
    case find(roster, plug_id) do
      %Plug{role: role} -> role
      nil -> nil
    end
  end

  @spec measured?(t, String.t()) :: boolean
  def measured?(roster, plug_id), do: Map.has_key?(@bucket_key_by_role, role_of(roster, plug_id))

  @spec bucket_key(t, String.t()) :: :production_w | :consumption_w
  def bucket_key(roster, plug_id), do: Map.fetch!(@bucket_key_by_role, role_of(roster, plug_id))

  @doc "Producers report with the opposite sign; their watts become a positive magnitude."
  @spec signed_watts(t, String.t(), float) :: float
  def signed_watts(roster, plug_id, watt) do
    if role_of(roster, plug_id) == :producer, do: abs(watt), else: watt
  end
end
