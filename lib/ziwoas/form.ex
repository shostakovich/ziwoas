defmodule Ziwoas.Form do
  @moduledoc """
  dry-validation's `params` contracts on Ecto changesets, so a form answers
  with Rails' messages in Rails' order (`test/vectors/forms.json`).

  `cast/3` is the schema step: every declared key is checked and coerced
  like dry-schema's Params processor — a required key that is absent is
  `"is missing"`, `maybe(:string)` turns `""` into nil and refuses anything
  but a string, an integer list coerces each element with `Integer(s, 10)`
  and keeps what it cannot. `rule/4` is a rule: it runs only for a key whose
  schema step passed. `messages/1` lists the schema errors in key order, then
  the rule errors in rule order — `result.errors.map(&:text)`.

  The changeset's changes are the contract's `to_h`: the keys that were
  given, coerced as far as they went.
  """
  import Ecto.Changeset

  alias Ziwoas.RubyNumeric

  @type field_spec :: {atom, {:required | :optional, :maybe_string | :integer_list}}

  @doc "The schema step over `spec` (`field: {presence, type}`, in the contract's key order)."
  @spec cast(struct, map, [field_spec]) :: Ecto.Changeset.t()
  def cast(data, params, spec) do
    Enum.reduce(spec, change(data), fn {field, {presence, type}}, changeset ->
      case Map.fetch(params, Atom.to_string(field)) do
        :error when presence == :required ->
          add_error(changeset, field, "is missing", validation: :schema)

        :error ->
          changeset

        {:ok, value} ->
          case coerce(type, value) do
            {:ok, coerced} ->
              force_change(changeset, field, coerced)

            {:error, kept, messages} ->
              Enum.reduce(
                messages,
                force_change(changeset, field, kept),
                &add_error(&2, field, &1, validation: :schema)
              )
          end
      end
    end)
  end

  @doc "Adds `message` on `field` when `failing?` holds for its value; skipped after a schema error."
  @spec rule(Ecto.Changeset.t(), atom, (term -> boolean), String.t()) :: Ecto.Changeset.t()
  def rule(changeset, field, failing?, message) do
    if passed_schema?(changeset, field) and failing?.(Map.get(changeset.changes, field)),
      do: add_error(changeset, field, message, validation: :rule),
      else: changeset
  end

  @spec messages(Ecto.Changeset.t()) :: [String.t()]
  def messages(changeset) do
    errors = Enum.reverse(changeset.errors)
    schema = for {_field, {message, [validation: :schema]}} <- errors, do: message
    rules = for {_field, {message, [validation: :rule]}} <- errors, do: message
    schema ++ rules
  end

  @doc "Ruby's `blank?` for what a form sends: nil, or a string of whitespace."
  @spec blank?(term) :: boolean
  def blank?(nil), do: true
  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(_value), do: false

  defp passed_schema?(changeset, field),
    do:
      Map.has_key?(changeset.changes, field) and
        not Enum.any?(changeset.errors, &match?({^field, {_, [validation: :schema]}}, &1))

  defp coerce(:maybe_string, value) when value in [nil, ""], do: {:ok, nil}
  defp coerce(:maybe_string, value) when is_binary(value), do: {:ok, value}
  defp coerce(:maybe_string, value), do: {:error, value, ["must be a string"]}

  defp coerce(:integer_list, values) when is_list(values) do
    coerced =
      Enum.map(values, fn value ->
        case RubyNumeric.integer(value) do
          {:ok, integer} -> {:ok, integer}
          :error -> {:error, value}
        end
      end)

    kept = Enum.map(coerced, &elem(&1, 1))

    # One message per element, as dry-schema reports `days.0`, `days.1`, …
    case for {:error, _} <- coerced, do: "must be an integer" do
      [] -> {:ok, kept}
      messages -> {:error, kept, messages}
    end
  end

  defp coerce(:integer_list, value), do: {:error, value, ["must be an array"]}
end
