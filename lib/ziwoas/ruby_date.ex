defmodule Ziwoas.RubyDate do
  @moduledoc """
  Ruby's `Date.iso8601` (date_parse.c `date__iso8601` + date_core.c
  `rt_complete_frags`), for request parameters Rails parses with it.

  Accepts what Ruby accepts: extended and basic calendar dates
  (`2026-03-29`, `20260329`, two-digit years as 1969–2068), ordinal
  (`2026-088`) and week dates (`2026-W13-7`), an ignored time part
  (`2026-03-29T12:00Z`), surrounding whitespace, and the forms that leave
  out leading fields (`--03-29`, `-088`, `-w-7`), which take them from
  `today`. Ruby fills those from the system date, not from `travel_to`.

  Ruby counts days before 1582-10-15 in the Julian calendar; this port is
  proleptic Gregorian throughout.
  """

  @limit 128

  @ext ~r/\A\s*(?:([-+]?\d{2,}|-)-(\d{2})?(?:-(\d{2}))?|([-+]?\d{2,})?-(\d{3})|(\d{4}|\d{2})?-w(\d{2})-(\d)|-w-(\d))(?:t(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?)?(z|[-+]\d{2}(?::?\d{2})?)?)?\s*\z/i
  @basic ~r/\A\s*(?:([-+]?(?:\d{4}|\d{2})|--)(\d{2}|-)(\d{2})|([-+]?(?:\d{4}|\d{2}))(\d{3})|-(\d{3})|(\d{4}|\d{2})w(\d{2})(\d)|-w(\d{2})(\d)|-w-(\d))(?:t?(\d{2})(\d{2})(?:(\d{2})(?:[,.](\d+))?)?(z|[-+]\d{2}(?:\d{2})?)?)?\s*\z/i

  @doc "The date `value` names, or nil where Ruby raises (`Date::Error`, over-long input)."
  @spec iso8601(term, Date.t()) :: Date.t() | nil
  def iso8601(value, today) when is_binary(value) and byte_size(value) <= @limit,
    do: value |> fragments() |> to_date(today)

  def iso8601(_value, _today), do: nil

  defp fragments(value) do
    {matched, frags} = ext(value)
    if matched, do: frags, else: Map.merge(frags, basic(value))
  end

  defp ext(value) do
    case Regex.run(@ext, value, capture: :all_but_first) do
      nil -> {false, %{}}
      groups -> ext_frags(pad(groups, 9))
    end
  end

  defp ext_frags([y, mon, mday | _]) when y != "" do
    frags = %{} |> put(:mday, mday) |> put_year(:year, if(y == "-", do: "", else: y))

    cond do
      mon != "" -> {true, put(frags, :mon, mon)}
      y == "-" -> {true, frags}
      true -> {false, frags}
    end
  end

  defp ext_frags([_, _, _, y, yday | _]) when yday != "",
    do: {true, %{} |> put(:yday, yday) |> put_year(:year, y)}

  defp ext_frags([_, _, _, _, _, y, cweek, cwday | _]) when cwday != "",
    do: {true, %{} |> put(:cweek, cweek) |> put(:cwday, cwday) |> put_year(:cwyear, y)}

  defp ext_frags([_, _, _, _, _, _, _, _, cwday]), do: {true, put(%{}, :cwday, cwday)}

  defp basic(value) do
    case Regex.run(@basic, value, capture: :all_but_first) do
      nil -> %{}
      groups -> groups |> pad(12) |> basic_frags()
    end
  end

  defp basic_frags([y, mon, mday | _]) when y != "" do
    frags = %{} |> put(:mday, mday) |> put_year(:year, if(y == "--", do: "", else: y))

    cond do
      mon != "-" -> put(frags, :mon, mon)
      y == "--" -> frags
      true -> %{}
    end
  end

  defp basic_frags([_, _, _, y, yday | _]) when yday != "",
    do: %{} |> put(:yday, yday) |> put_year(:year, y)

  defp basic_frags([_, _, _, _, _, yday | _]) when yday != "", do: put(%{}, :yday, yday)

  defp basic_frags([_, _, _, _, _, _, y, cweek, cwday | _]) when cwday != "",
    do: %{} |> put(:cweek, cweek) |> put(:cwday, cwday) |> put_year(:cwyear, y)

  defp basic_frags([_, _, _, _, _, _, _, _, _, cweek, cwday, _]) when cwday != "",
    do: %{} |> put(:cweek, cweek) |> put(:cwday, cwday)

  defp basic_frags([_, _, _, _, _, _, _, _, _, _, _, cwday]), do: put(%{}, :cwday, cwday)

  defp pad(groups, size), do: Enum.take(groups ++ List.duplicate("", size), size)

  defp put(frags, _key, ""), do: frags
  defp put(frags, key, digits), do: Map.put(frags, key, String.to_integer(digits))

  # Fewer than four characters (sign included) is a two-digit year: 69–99 → 19xx, else 20xx.
  defp put_year(frags, _key, ""), do: frags

  defp put_year(frags, key, text) do
    year = String.to_integer(text)

    year =
      if String.length(text) < 4,
        do: if(year >= 69, do: year + 1900, else: year + 2000),
        else: year

    Map.put(frags, key, year)
  end

  # rt_complete_frags: the pattern with the most fields present wins; leading
  # gaps come from today, trailing ones default to 1.
  defp to_date(frags, _today) when map_size(frags) == 0, do: nil

  defp to_date(%{yday: yday} = frags, today), do: ordinal(Map.get(frags, :year, today.year), yday)

  defp to_date(%{cwday: _} = frags, today) do
    {today_cwyear, today_cweek} = :calendar.iso_week_number(Date.to_erl(today))

    case frags do
      %{cwyear: y} -> commercial(y, Map.get(frags, :cweek, 1), frags.cwday)
      %{cweek: w} -> commercial(today_cwyear, w, frags.cwday)
      _ -> commercial(today_cwyear, today_cweek, frags.cwday)
    end
  end

  defp to_date(frags, today) do
    {year, mon, mday} =
      case frags do
        %{year: y} -> {y, Map.get(frags, :mon, 1), Map.get(frags, :mday, 1)}
        %{mon: m} -> {today.year, m, Map.get(frags, :mday, 1)}
        %{mday: d} -> {today.year, today.month, d}
      end

    case Date.new(year, mon, mday) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp ordinal(year, yday) do
    with true <- yday >= 1,
         {:ok, first} <- Date.new(year, 1, 1),
         %Date{year: ^year} = date <- Date.add(first, yday - 1) do
      date
    else
      _ -> nil
    end
  end

  defp commercial(cwyear, cweek, cwday) when cwday in 1..7 and cweek >= 1 do
    with {:ok, jan4} <- Date.new(cwyear, 1, 4) do
      monday = Date.add(jan4, 1 - Date.day_of_week(jan4))
      date = Date.add(monday, (cweek - 1) * 7 + cwday - 1)
      if :calendar.iso_week_number(Date.to_erl(date)) == {cwyear, cweek}, do: date
    else
      _ -> nil
    end
  end

  defp commercial(_cwyear, _cweek, _cwday), do: nil
end
