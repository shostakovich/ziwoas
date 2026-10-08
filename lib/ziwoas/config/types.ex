defmodule Ziwoas.Config.Types do
  @moduledoc false

  @spec cast_message(atom, keyword) :: String.t() | nil
  def cast_message(_field, meta) do
    case meta[:type] do
      :string -> "must be a string"
      {:parameterized, {Ecto.Enum, %{mappings: mappings}}} -> one_of(mappings)
      _ -> nil
    end
  end

  defp one_of(mappings), do: "must be one of " <> Enum.map_join(mappings, ", ", &elem(&1, 1))

  defmodule Text do
    @moduledoc false
    use Ecto.Type

    def type, do: :string

    def cast(value) when is_binary(value), do: {:ok, value}
    def cast(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
    def cast(value) when is_float(value), do: {:ok, Float.to_string(value)}
    def cast(value) when is_boolean(value), do: {:ok, Atom.to_string(value)}
    def cast(_value), do: {:error, message: "must be text"}

    def load(value), do: {:ok, value}
    def dump(value), do: {:ok, value}
  end

  defmodule Count do
    @moduledoc false
    use Ecto.Type

    def type, do: :integer

    def cast(value) when is_integer(value), do: {:ok, value}
    def cast(value) when is_float(value), do: {:ok, trunc(value)}

    def cast(value) when is_binary(value) do
      case Integer.parse(String.trim(value)) do
        {integer, _rest} -> {:ok, integer}
        :error -> invalid()
      end
    end

    def cast(_value), do: invalid()

    defp invalid, do: {:error, message: "must be a number"}

    def load(value), do: {:ok, value}
    def dump(value), do: {:ok, value}
  end

  defmodule Number do
    @moduledoc false
    use Ecto.Type

    def type, do: :float

    def cast(value) when is_number(value), do: {:ok, value}

    def cast(value) when is_binary(value) do
      text = String.trim(value)

      case {Integer.parse(text), Float.parse(text)} do
        {{integer, ""}, _} -> {:ok, integer}
        {_, {float, ""}} -> {:ok, float}
        _ -> {:error, message: "must be a number"}
      end
    end

    def cast(_value), do: {:error, message: "must be a number"}

    def load(value), do: {:ok, value}
    def dump(value), do: {:ok, value}
  end

  defmodule Real do
    @moduledoc false
    use Ecto.Type

    def type, do: :float

    def cast(value) do
      case Number.cast(value) do
        {:ok, number} -> {:ok, number * 1.0}
        error -> error
      end
    end

    def load(value), do: {:ok, value}
    def dump(value), do: {:ok, value}
  end

  defmodule Flag do
    @moduledoc false
    use Ecto.Type

    def type, do: :boolean

    def cast(value) when is_boolean(value), do: {:ok, value}
    def cast(_value), do: {:error, message: "must be true or false"}

    def load(value), do: {:ok, value}
    def dump(value), do: {:ok, value}
  end
end
