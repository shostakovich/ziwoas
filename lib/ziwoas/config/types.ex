defmodule Ziwoas.Config.Types do
  @moduledoc """
  The Ecto types `Ziwoas.Config` casts YAML scalars with. They are as lenient as
  the config always was: `"1883 "` reads as 1883, `8.0` as 8, a bare number as
  text, but a flag is only an unquoted YAML boolean.
  """

  @doc "The message for a value that does not cast, for `Ecto.Changeset.cast/4`'s `:message`."
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
    @moduledoc "Text; a number or a boolean reads as its text."
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
    @moduledoc "An integer: a float is truncated, text read up to its first non-digit."
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
    @moduledoc "A number as written; text must be nothing but a number."
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
    @moduledoc "A number as a float; text must be nothing but a number."
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
    @moduledoc "A YAML boolean (`true`, `yes`, `on`, …); text is not one."
    use Ecto.Type

    def type, do: :boolean

    def cast(value) when is_boolean(value), do: {:ok, value}
    def cast(_value), do: {:error, message: "must be true or false"}

    def load(value), do: {:ok, value}
    def dump(value), do: {:ok, value}
  end
end
