defmodule Ziwoas.RubyJSON do
  @moduledoc """
  JSON exactly as Rails writes it (`ActiveSupport::JSON.encode`, which jbuilder
  and `Hash#to_json` go through), so ported endpoints are byte-identical:

    * objects keep their key order: pass them as a list of `{key, value}`
      pairs (`[{"a", 1}]`); an empty object is `%{}`. Maps are accepted too,
      with keys sorted, for the cases where Rails' order is not observable;
    * floats come from the json gem's fpconv (Grisu2) port in
      `Ziwoas.RubyJSON.Float` (`0.00001`, `1e+16`), non-finite ones
      (`:nan`, `:infinity`, `:neg_infinity`) are `null` like `Float#as_json`;
    * strings escape `<`, `>` and `&` as `\\u003c`, `\\u003e`, `\\u0026`
      (`escape_html_entities_in_json`), control characters as the json gem
      does, and leave everything else, `/` and U+2028 included, as is;
    * atoms are strings (Symbol), `Date`s are `"YYYY-MM-DD"`.

  `generate!/1` is Ruby's plain `JSON.generate` (what the MQTT payloads go through):
  the same bytes without the HTML-entity escaping.
  """
  alias Ziwoas.RubyJSON.Float, as: RubyFloat

  @spec encode!(term) :: String.t()
  def encode!(value), do: value |> encode(true) |> IO.iodata_to_binary()

  @spec generate!(term) :: String.t()
  def generate!(value), do: value |> encode(false) |> IO.iodata_to_binary()

  defp encode(nil, _html), do: "null"
  defp encode(true, _html), do: "true"
  defp encode(false, _html), do: "false"
  defp encode(value, _html) when value in [:nan, :infinity, :neg_infinity], do: "null"
  defp encode(value, html) when is_atom(value), do: value |> Atom.to_string() |> string(html)
  defp encode(value, _html) when is_integer(value), do: Integer.to_string(value)
  defp encode(value, _html) when is_float(value), do: RubyFloat.to_json(value)
  defp encode(value, html) when is_binary(value), do: string(value, html)
  defp encode(%Date{} = date, html), do: date |> Date.to_iso8601() |> string(html)
  defp encode([{_key, _value} | _] = pairs, html), do: object(pairs, html)

  defp encode(list, html) when is_list(list),
    do: ["[", list |> Enum.map(&encode(&1, html)) |> Enum.intersperse(","), "]"]

  defp encode(%_{} = struct, _html),
    do: raise(ArgumentError, "no Rails JSON encoding for #{inspect(struct.__struct__)}")

  defp encode(map, html) when is_map(map),
    do: map |> Enum.sort_by(fn {key, _} -> key_string(key) end) |> object(html)

  defp object([], _html), do: "{}"

  defp object(pairs, html) do
    members =
      Enum.map(pairs, fn {key, value} ->
        [string(key_string(key), html), ":", encode(value, html)]
      end)

    ["{", Enum.intersperse(members, ","), "}"]
  end

  defp key_string(key) when is_binary(key), do: key
  defp key_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_string(key) when is_integer(key), do: Integer.to_string(key)

  @doc "A JSON string literal with Rails' escaping."
  @spec string(String.t()) :: iodata
  def string(text), do: string(text, true)

  defp string(text, html), do: [?", escape(text, html, []), ?"]

  defp escape(<<>>, _html, acc), do: Enum.reverse(acc)
  defp escape(<<?", rest::binary>>, html, acc), do: escape(rest, html, ["\\\"" | acc])
  defp escape(<<?\\, rest::binary>>, html, acc), do: escape(rest, html, ["\\\\" | acc])
  defp escape(<<?\b, rest::binary>>, html, acc), do: escape(rest, html, ["\\b" | acc])
  defp escape(<<?\f, rest::binary>>, html, acc), do: escape(rest, html, ["\\f" | acc])
  defp escape(<<?\n, rest::binary>>, html, acc), do: escape(rest, html, ["\\n" | acc])
  defp escape(<<?\r, rest::binary>>, html, acc), do: escape(rest, html, ["\\r" | acc])
  defp escape(<<?\t, rest::binary>>, html, acc), do: escape(rest, html, ["\\t" | acc])
  defp escape(<<?<, rest::binary>>, true, acc), do: escape(rest, true, ["\\u003c" | acc])
  defp escape(<<?>, rest::binary>>, true, acc), do: escape(rest, true, ["\\u003e" | acc])
  defp escape(<<?&, rest::binary>>, true, acc), do: escape(rest, true, ["\\u0026" | acc])

  defp escape(<<byte, rest::binary>>, html, acc) when byte < 0x20,
    do: escape(rest, html, [unicode_escape(byte) | acc])

  defp escape(<<byte, rest::binary>>, html, acc), do: escape(rest, html, [byte | acc])

  defp unicode_escape(byte),
    do: "\\u" <> String.pad_leading(Integer.to_string(byte, 16) |> String.downcase(), 4, "0")
end
