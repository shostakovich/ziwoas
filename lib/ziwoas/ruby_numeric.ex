defmodule Ziwoas.RubyNumeric do
  @moduledoc """
  Ruby's numeric semantics where the Rails cores lean on them, pinned by
  `test/vectors/ruby_numeric.json`.

  Erlang floats have no NaN or infinities. Where Ruby would produce one, these
  functions return `:nan`, `:infinity` or `:neg_infinity` instead of raising.
  """
  import Bitwise

  @type extended :: number | :nan | :infinity | :neg_infinity

  @infinities [:infinity, :neg_infinity]

  @doc """
  `Float#round(digits)`: half away from zero plus Ruby's correction step
  (`round_half_up` in float.c), so 2.675 → 2.68 and 1.005 → 1.01 where
  `Float.round/2` rounds the binary value (2.67, 1.0). Zero digits answer an
  Integer, like Ruby. Integers stay as they are.
  """
  @spec round(number, non_neg_integer) :: number
  def round(value, digits) when is_integer(value) and is_integer(digits) and digits >= 0,
    do: value

  def round(value, 0) when is_float(value), do: Kernel.round(value)

  def round(value, digits) when is_float(value) and digits in 1..14 do
    binexp = frexp_exponent(value)

    cond do
      value == 0.0 -> value
      round_overflow?(digits, binexp) -> value
      round_underflow?(digits, binexp) -> 0.0
      true -> round_half_up(value, :math.pow(10.0, digits)) / :math.pow(10.0, digits)
    end
  end

  # float.c: the scaled value would already be integral, so rounding changes nothing.
  defp round_overflow?(digits, binexp),
    do: digits >= 17 - if(binexp > 0, do: div(binexp, 4), else: div(binexp, 3) - 1)

  defp round_underflow?(digits, binexp),
    do: digits < -if(binexp > 0, do: div(binexp, 3) + 1, else: div(binexp, 4))

  defp round_half_up(x, s) do
    f = c_round(x * s)

    cond do
      x > 0 and (f + 0.5) / s <= x -> f + 1
      x < 0 and (f - 0.5) / s >= x -> f - 1
      true -> f
    end
  end

  # C's round(): half away from zero, keeping the sign of a negative zero.
  defp c_round(x) do
    case Kernel.round(x) do
      0 when x < 0 -> -0.0
      r -> :erlang.float(r)
    end
  end

  # The exponent frexp(3) reports: |x| = m * 2^e with 0.5 <= m < 1.
  defp frexp_exponent(x) do
    <<_sign::1, exponent::11, mantissa::52>> = <<x::float>>
    if exponent == 0, do: length(Integer.digits(mantissa, 2)) - 1074, else: exponent - 1022
  end

  @doc """
  `Array#sum` / `Enumerable#sum`: integers add up exactly until the first float,
  from there on Kahan-Babuska compensated summation. An empty list is the
  Integer 0.
  """
  @spec sum([extended]) :: extended
  def sum(values), do: sum_exact(values, 0)

  defp sum_exact([], acc), do: acc
  defp sum_exact([x | rest], acc) when is_integer(x), do: sum_exact(rest, acc + x)
  defp sum_exact(values, acc), do: kahan(values, :erlang.float(acc), 0.0)

  defp kahan([], f, c), do: add(f, c)
  defp kahan([x | rest], f, c) when is_integer(x), do: kahan([:erlang.float(x) | rest], f, c)
  defp kahan([_ | rest], :nan, c), do: kahan(rest, :nan, c)
  defp kahan([:nan | rest], _f, c), do: kahan(rest, :nan, c)

  defp kahan([x | rest], f, c) when x in @infinities do
    f = if f in @infinities and f != x, do: :nan, else: x
    kahan(rest, f, c)
  end

  defp kahan([_ | rest], f, c) when f in @infinities, do: kahan(rest, f, c)

  defp kahan([x | rest], f, c) do
    t = add(f, x)

    correction =
      if abs(f) >= abs(x), do: add(subtract(f, t), x), else: add(subtract(x, t), f)

    kahan(rest, t, add(c, correction))
  end

  @doc "IEEE 754 addition over floats, integers and the three non-finite atoms."
  @spec add(extended, extended) :: extended
  def add(:nan, _), do: :nan
  def add(_, :nan), do: :nan
  def add(:infinity, :neg_infinity), do: :nan
  def add(:neg_infinity, :infinity), do: :nan
  def add(a, _) when a in @infinities, do: a
  def add(_, b) when b in @infinities, do: b

  def add(a, b) do
    a + b
  rescue
    ArithmeticError -> if a > 0, do: :infinity, else: :neg_infinity
  end

  defp subtract(a, b), do: add(a, negate(b))

  defp negate(:infinity), do: :neg_infinity
  defp negate(:neg_infinity), do: :infinity
  defp negate(:nan), do: :nan
  defp negate(x), do: -x

  @doc """
  `Array#min`: the first of equal minima wins, so `[0, 0.0].min` stays the
  Integer 0 and `[-0.0, 0.0].min` keeps the negative zero.
  """
  @spec min([number, ...]) :: number
  def min([first | rest]),
    do: Enum.reduce(rest, first, fn x, acc -> if x < acc, do: x, else: acc end)

  @doc "`Array#max`: the first of equal maxima wins."
  @spec max([number, ...]) :: number
  def max([first | rest]),
    do: Enum.reduce(rest, first, fn x, acc -> if x > acc, do: x, else: acc end)

  @doc "`Kernel#format(\"%.Nf\", float)`: the exact binary value, rounded half to even."
  @spec format_fixed(float, non_neg_integer) :: String.t()
  def format_fixed(value, digits) when is_float(value) do
    {numerator, denominator} = exact(value)
    scaled = abs(numerator) * 10 ** digits
    quotient = div(scaled, denominator)
    twice_rest = 2 * rem(scaled, denominator)

    quotient =
      if twice_rest > denominator or (twice_rest == denominator and rem(quotient, 2) == 1),
        do: quotient + 1,
        else: quotient

    sign = if negative_sign?(value), do: "-", else: ""
    sign <> insert_point(Integer.to_string(quotient), digits)
  end

  defp insert_point(text, 0), do: text

  defp insert_point(text, digits) do
    {integer, fraction} = text |> String.pad_leading(digits + 1, "0") |> String.split_at(-digits)
    integer <> "." <> fraction
  end

  defp negative_sign?(value), do: match?(<<1::1, _::63>>, <<value::float>>)

  @doc """
  The exact value of a finite float as `{numerator, denominator}`, the
  denominator a power of two. Ruby does exact arithmetic with it where a float
  meets a Time or a BigDecimal.
  """
  @spec exact(float) :: {integer, pos_integer}
  def exact(value) when is_float(value) do
    <<sign::1, exponent::11, mantissa::52>> = <<value::float>>

    {mantissa, power} =
      if exponent == 0, do: {mantissa, -1074}, else: {mantissa ||| 1 <<< 52, exponent - 1075}

    mantissa = if sign == 1, do: -mantissa, else: mantissa
    if power >= 0, do: {mantissa <<< power, 1}, else: {mantissa, 1 <<< -power}
  end

  @doc "`Kernel#Integer`: integers, floats truncated, and strict integer strings."
  @spec integer!(integer | float | String.t()) :: integer
  def integer!(value) when is_integer(value), do: value
  def integer!(value) when is_float(value), do: trunc(value)

  def integer!(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _ -> raise ArgumentError, "invalid value for Integer(): #{inspect(value)}"
    end
  end

  @doc "`#to_i` as Ruby's String, Float and NilClass answer it: lenient, never raising."
  @spec to_i(term) :: integer
  def to_i(nil), do: 0
  def to_i(value) when is_integer(value), do: value
  def to_i(value) when is_float(value), do: trunc(value)

  def to_i(value) when is_binary(value) do
    case Integer.parse(String.trim_leading(value)) do
      {integer, _rest} -> integer
      :error -> 0
    end
  end

  @leading_float ~r/\A\s*(?<sign>[+-]?)(?<int>\d*)(?:\.(?<frac>\d+))?(?:[eE](?<exp>[+-]?\d+))?/

  @doc "`#to_f` as Ruby's String, Integer and NilClass answer it: the longest numeric prefix, else 0.0."
  @spec to_f(term) :: float
  def to_f(nil), do: 0.0
  def to_f(value) when is_float(value), do: value
  def to_f(value) when is_integer(value), do: :erlang.float(value)

  def to_f(value) when is_binary(value) do
    case Regex.named_captures(@leading_float, value) do
      %{"int" => "", "frac" => ""} ->
        0.0

      %{"sign" => sign, "int" => int, "frac" => frac, "exp" => exp} ->
        String.to_float(
          "#{sign}#{zero_if_empty(int)}.#{zero_if_empty(frac)}e#{zero_if_empty(exp)}"
        )
    end
  end

  defp zero_if_empty(""), do: "0"
  defp zero_if_empty(digits), do: digits

  # Ruby's ISSPACE, what Float() and Integer() strip around a string.
  @space "[ \\t\\n\\x0B\\f\\r]*"
  @digits "\\d+(?:_\\d+)*"
  @hex_digits "[0-9a-fA-F]+(?:_[0-9a-fA-F]+)*"
  @strict_decimal Regex.compile!(
                    "\\A#{@space}([+-]?)(#{@digits})?(?:\\.(#{@digits})?)?(?:[eE]([+-]?#{@digits}))?#{@space}\\z"
                  )
  @strict_hex Regex.compile!(
                "\\A#{@space}([+-]?)0[xX](#{@hex_digits})?(?:\\.(#{@hex_digits})?)?(?:[pP]([+-]?\\d+))?#{@space}\\z"
              )
  @strict_integer Regex.compile!("\\A#{@space}([+-]?)(?:0[dD])?(#{@digits})#{@space}\\z")

  @doc """
  `Kernel#Float(string)`: the whole string must be a number — decimal with
  underscores between digits (`1_000`, `.5`, `5.`, `1e3`) or hexadecimal
  (`0x1A`, `0x1.8p1`), surrounding whitespace allowed. `:infinity` or
  `:neg_infinity` where Ruby overflows (`1e400`), `:error` where it raises.
  """
  @spec float(term) :: {:ok, float | :infinity | :neg_infinity} | :error
  def float(value) when is_binary(value) do
    cond do
      String.contains?(value, <<0>>) -> :error
      match = Regex.run(@strict_hex, value, capture: :all_but_first) -> hex_float(pad(match, 4))
      match = Regex.run(@strict_decimal, value, capture: :all_but_first) -> decimal(pad(match, 4))
      true -> :error
    end
  end

  def float(_value), do: :error

  @doc "`Kernel#Integer(string, 10)`: whitespace, a sign, `0d`, underscores between digits."
  @spec integer(term) :: {:ok, integer} | :error
  def integer(value) when is_binary(value) do
    case Regex.run(@strict_integer, value, capture: :all_but_first) do
      [sign, digits] -> {:ok, String.to_integer(sign <> String.replace(digits, "_", ""))}
      nil -> :error
    end
  end

  def integer(_value), do: :error

  defp pad(groups, size), do: groups ++ List.duplicate("", size - length(groups))

  defp decimal([_sign, "", "", _exp]), do: :error

  defp decimal([sign, int, frac, exp]) do
    text =
      "#{sign}#{zero_if_empty(int)}.#{zero_if_empty(frac)}e#{zero_if_empty(exp)}"
      |> String.replace("_", "")

    case Float.parse(text) do
      {float, ""} -> {:ok, float}
      # Valid syntax that Erlang cannot hold: Ruby's HUGE_VAL.
      :error -> {:ok, if(sign == "-", do: :neg_infinity, else: :infinity)}
    end
  end

  defp hex_float([_sign, "", "", _exp]), do: :error

  defp hex_float([sign, int, frac, exp]) do
    int = String.replace(int, "_", "")
    frac = String.replace(frac, "_", "")
    mantissa = String.to_integer(zero_if_empty(int <> frac), 16)
    power = String.to_integer(zero_if_empty(exp)) - 4 * byte_size(frac)
    magnitude = scale_binary(mantissa, power)

    cond do
      magnitude == :infinity and sign == "-" -> {:ok, :neg_infinity}
      magnitude == :infinity -> {:ok, :infinity}
      sign == "-" -> {:ok, -magnitude}
      true -> {:ok, magnitude}
    end
  end

  defp scale_binary(mantissa, power) when power >= 0 do
    value = mantissa <<< power
    if value > 1.7976931348623157e308, do: :infinity, else: :erlang.float(value)
  end

  defp scale_binary(mantissa, power), do: mantissa / (1 <<< -power)

  @doc """
  `#to_s` of an Integer or Float as Ruby prints it, e.g. into an ERB template:
  the shortest round-tripping digits, fixed notation for decimal exponents
  -4 < e <= 15 (`100.0`, `0.001`), else `1.0e+15` / `1.0e-05`.
  """
  @spec to_s(number) :: String.t()
  def to_s(value) when is_integer(value), do: Integer.to_string(value)

  def to_s(value) when is_float(value) do
    sign = if negative_sign?(value), do: "-", else: ""
    {digits, decpt} = shortest_digits(abs(value))
    sign <> float_text(digits, decpt)
  end

  defp float_text("0", _decpt), do: "0.0"

  defp float_text(digits, decpt) when decpt > 0 and decpt <= 15 do
    {integer, fraction} =
      if byte_size(digits) <= decpt,
        do: {digits <> String.duplicate("0", decpt - byte_size(digits)), "0"},
        else: String.split_at(digits, decpt)

    integer <> "." <> fraction
  end

  defp float_text(digits, decpt) when decpt <= 0 and decpt > -4,
    do: "0." <> String.duplicate("0", -decpt) <> digits

  defp float_text(digits, decpt) do
    {first, rest} = String.split_at(digits, 1)
    first <> "." <> if(rest == "", do: "0", else: rest) <> "e" <> exponent_text(decpt - 1)
  end

  defp exponent_text(exponent) do
    sign = if exponent < 0, do: "-", else: "+"
    sign <> String.pad_leading(Integer.to_string(abs(exponent)), 2, "0")
  end

  # Shortest digits (no leading or trailing zeros) and the decimal point's
  # position: value = 0.DIGITS × 10^decpt.
  defp shortest_digits(value) when value == 0.0, do: {"0", 1}

  defp shortest_digits(value) do
    {mantissa, exponent} =
      case String.split(:erlang.float_to_binary(value, [:short]), "e") do
        [mantissa, exponent] -> {mantissa, String.to_integer(exponent)}
        [mantissa] -> {mantissa, 0}
      end

    [integer, fraction] = String.split(mantissa, ".")
    normalize_digits(integer <> fraction, byte_size(integer) + exponent)
  end

  defp normalize_digits("0" <> rest, decpt) when rest != "", do: normalize_digits(rest, decpt - 1)

  defp normalize_digits(digits, decpt) do
    trimmed = String.trim_trailing(digits, "0")
    {if(trimmed == "", do: "0", else: trimmed), decpt}
  end

  @doc "`Kernel#format(\"%g\", number)`: six significant digits, trailing zeros dropped."
  @spec format_g(number) :: String.t()
  def format_g(value) when is_integer(value), do: format_g(:erlang.float(value))

  def format_g(value) when is_float(value) do
    sign = if negative_sign?(value), do: "-", else: ""
    [mantissa, exponent] = String.split(:erlang.float_to_binary(abs(value), scientific: 5), "e")
    exponent = String.to_integer(exponent)
    digits = String.replace(mantissa, ".", "")

    text =
      cond do
        value == 0.0 ->
          "0"

        exponent < -4 or exponent >= 6 ->
          {first, rest} = String.split_at(digits, 1)
          rest = String.trim_trailing(rest, "0")
          first <> if(rest == "", do: "", else: "." <> rest) <> "e" <> exponent_text(exponent)

        exponent >= 0 ->
          {integer, fraction} = String.split_at(digits, exponent + 1)
          trim_fraction(integer, fraction)

        true ->
          trim_fraction("0", String.duplicate("0", -exponent - 1) <> digits)
      end

    sign <> text
  end

  defp trim_fraction(integer, fraction) do
    case String.trim_trailing(fraction, "0") do
      "" -> integer
      fraction -> integer <> "." <> fraction
    end
  end
end
