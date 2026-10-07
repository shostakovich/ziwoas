defmodule Ziwoas.RubyJSON.Float do
  @moduledoc """
  Floats as the json gem (2.10+) writes them: Grisu2 digits from its vendored
  fpconv (ext/json/ext/vendor/fpconv.c), not `Float#to_s` and not Erlang's
  shortest form. Grisu2 is not always the shortest round-trip, and the layout
  differs from both (`0.00001` vs `1.0e-05`, `1e+16` vs `1.0e+16`), so this
  is a line-by-line port with C's unsigned 64-bit wraparound made explicit.
  """
  import Bitwise

  @mask 0xFFFF_FFFF_FFFF_FFFF
  @frac_mask 0x000F_FFFF_FFFF_FFFF
  @exp_mask 0x7FF0_0000_0000_0000
  @hidden_bit 0x0010_0000_0000_0000
  @exp_bias 1023 + 52
  @n_powers 87
  @step_powers 8
  @first_power -348
  @exp_max -32
  @exp_min -60

  @powers_ten {
    {18_054_884_314_459_144_840, -1220},
    {13_451_937_075_301_367_670, -1193},
    {10_022_474_136_428_063_862, -1166},
    {14_934_650_266_808_366_570, -1140},
    {11_127_181_549_972_568_877, -1113},
    {16_580_792_590_934_885_855, -1087},
    {12_353_653_155_963_782_858, -1060},
    {18_408_377_700_990_114_895, -1034},
    {13_715_310_171_984_221_708, -1007},
    {10_218_702_384_817_765_436, -980},
    {15_227_053_142_812_498_563, -954},
    {11_345_038_669_416_679_861, -927},
    {16_905_424_996_341_287_883, -901},
    {12_595_523_146_049_147_757, -874},
    {9_384_396_036_005_875_287, -847},
    {13_983_839_803_942_852_151, -821},
    {10_418_772_551_374_772_303, -794},
    {15_525_180_923_007_089_351, -768},
    {11_567_161_174_868_858_868, -741},
    {17_236_413_322_193_710_309, -715},
    {12_842_128_665_889_583_758, -688},
    {9_568_131_466_127_621_947, -661},
    {14_257_626_930_069_360_058, -635},
    {10_622_759_856_335_341_974, -608},
    {15_829_145_694_278_690_180, -582},
    {11_793_632_577_567_316_726, -555},
    {17_573_882_009_934_360_870, -529},
    {13_093_562_431_584_567_480, -502},
    {9_755_464_219_737_475_723, -475},
    {14_536_774_485_912_137_811, -449},
    {10_830_740_992_659_433_045, -422},
    {16_139_061_738_043_178_685, -396},
    {12_024_538_023_802_026_127, -369},
    {17_917_957_937_422_433_684, -343},
    {13_349_918_974_505_688_015, -316},
    {9_946_464_728_195_732_843, -289},
    {14_821_387_422_376_473_014, -263},
    {11_042_794_154_864_902_060, -236},
    {16_455_045_573_212_060_422, -210},
    {12_259_964_326_927_110_867, -183},
    {18_268_770_466_636_286_478, -157},
    {13_611_294_676_837_538_539, -130},
    {10_141_204_801_825_835_212, -103},
    {15_111_572_745_182_864_684, -77},
    {11_258_999_068_426_240_000, -50},
    {16_777_216_000_000_000_000, -24},
    {12_500_000_000_000_000_000, 3},
    {9_313_225_746_154_785_156, 30},
    {13_877_787_807_814_456_755, 56},
    {10_339_757_656_912_845_936, 83},
    {15_407_439_555_097_886_824, 109},
    {11_479_437_019_748_901_445, 136},
    {17_105_694_144_590_052_135, 162},
    {12_744_735_289_059_618_216, 189},
    {9_495_567_745_759_798_747, 216},
    {14_149_498_560_666_738_074, 242},
    {10_542_197_943_230_523_224, 269},
    {15_709_099_088_952_724_970, 295},
    {11_704_190_886_730_495_818, 322},
    {17_440_603_504_673_385_349, 348},
    {12_994_262_207_056_124_023, 375},
    {9_681_479_787_123_295_682, 402},
    {14_426_529_090_290_212_157, 428},
    {10_748_601_772_107_342_003, 455},
    {16_016_664_761_464_807_395, 481},
    {11_933_345_169_920_330_789, 508},
    {17_782_069_995_880_619_868, 534},
    {13_248_674_568_444_952_270, 561},
    {9_871_031_767_461_413_346, 588},
    {14_708_983_551_653_345_445, 614},
    {10_959_046_745_042_015_199, 641},
    {16_330_252_207_878_254_650, 667},
    {12_166_986_024_289_022_870, 694},
    {18_130_221_999_122_236_476, 720},
    {13_508_068_024_458_167_312, 747},
    {10_064_294_952_495_520_794, 774},
    {14_996_968_138_956_309_548, 800},
    {11_173_611_982_879_273_257, 827},
    {16_649_979_327_439_178_909, 853},
    {12_405_201_291_620_119_593, 880},
    {9_242_595_204_427_927_429, 907},
    {13_772_540_099_066_387_757, 933},
    {10_261_342_003_245_940_623, 960},
    {15_290_591_125_556_738_113, 986},
    {11_392_378_155_556_871_081, 1013},
    {16_975_966_327_722_178_521, 1039},
    {12_648_080_533_535_911_531, 1066}
  }

  # tens[i] = 10^(19 - i)
  @tens List.to_tuple(for i <- 19..0//-1, do: Integer.pow(10, i))

  @doc "The JSON text of a finite float."
  @spec to_json(float) :: String.t()
  def to_json(value) when is_float(value) do
    <<bits::64>> = <<value::float>>
    sign = if bits >>> 63 == 1, do: "-", else: ""

    if value == 0.0 do
      sign <> "0.0"
    else
      {digits, k} = grisu2(bits)
      sign <> emit_digits(digits, k, sign == "-")
    end
  end

  # --- Grisu2 ------------------------------------------------------------------

  defp grisu2(bits) do
    w = build_fp(bits)
    {lower, upper} = normalized_boundaries(w)
    w = normalize(w)
    {cp, k} = cached_pow10(elem(upper, 1))

    w = multiply(w, cp)
    {upper_frac, upper_exp} = multiply(upper, cp)
    {lower_frac, lower_exp} = multiply(lower, cp)

    lower = {u64(lower_frac + 1), lower_exp}
    upper = {u64(upper_frac - 1), upper_exp}

    generate_digits(w, upper, lower, -k)
  end

  defp build_fp(bits) do
    frac = bits &&& @frac_mask
    exp = (bits &&& @exp_mask) >>> 52

    if exp != 0,
      do: {frac + @hidden_bit, exp - @exp_bias},
      else: {frac, -@exp_bias + 1}
  end

  defp normalize({frac, exp}) do
    {frac, exp} = shift_until(frac, exp, @hidden_bit)
    {u64(frac <<< 11), exp - 11}
  end

  defp shift_until(frac, exp, bit) do
    if (frac &&& bit) == 0, do: shift_until(u64(frac <<< 1), exp - 1, bit), else: {frac, exp}
  end

  defp normalized_boundaries({frac, exp}) do
    {upper_frac, upper_exp} = shift_until(u64((frac <<< 1) + 1), exp - 1, @hidden_bit <<< 1)
    upper = {u64(upper_frac <<< 10), upper_exp - 10}

    l_shift = if frac == @hidden_bit, do: 2, else: 1
    lower_frac = u64((frac <<< l_shift) - 1)
    lower_exp = exp - l_shift
    lower = {u64(lower_frac <<< (lower_exp - elem(upper, 1))), elem(upper, 1)}

    {lower, upper}
  end

  defp cached_pow10(exp) do
    approx = trunc(-(exp + @n_powers) * 0.30102999566398114)
    find_pow10(div(approx - @first_power, @step_powers), exp)
  end

  defp find_pow10(idx, exp) do
    {_frac, power_exp} = power = elem(@powers_ten, idx)
    current = exp + power_exp + 64

    cond do
      current < @exp_min -> find_pow10(idx + 1, exp)
      current > @exp_max -> find_pow10(idx - 1, exp)
      true -> {power, @first_power + idx * @step_powers}
    end
  end

  defp multiply({a, a_exp}, {b, b_exp}) do
    lo = 0xFFFF_FFFF
    ah_bl = (a >>> 32) * (b &&& lo)
    al_bh = (a &&& lo) * (b >>> 32)
    al_bl = (a &&& lo) * (b &&& lo)
    ah_bh = (a >>> 32) * (b >>> 32)

    tmp = (ah_bl &&& lo) + (al_bh &&& lo) + (al_bl >>> 32) + (1 <<< 31)
    {u64(ah_bh + (ah_bl >>> 32) + (al_bh >>> 32) + (tmp >>> 32)), a_exp + b_exp + 64}
  end

  defp generate_digits({w_frac, _}, {upper_frac, upper_exp}, {lower_frac, _}, k) do
    wfrac = u64(upper_frac - w_frac)
    delta = u64(upper_frac - lower_frac)
    shift = -upper_exp
    one = 1 <<< shift

    part1 = upper_frac >>> shift
    part2 = upper_frac &&& one - 1

    integral_digits(%{
      digits: [],
      part1: part1,
      part2: part2,
      delta: delta,
      wfrac: wfrac,
      one: one,
      shift: shift,
      kappa: 10,
      divp: 10,
      k: k
    })
  end

  defp integral_digits(%{kappa: 0} = s), do: fraction_digits(s, 18)

  defp integral_digits(s) do
    div = elem(@tens, s.divp)
    digit = div(s.part1, div)
    digits = push_digit(s.digits, digit)
    part1 = s.part1 - digit * div
    kappa = s.kappa - 1
    tmp = u64((part1 <<< s.shift) + s.part2)

    if tmp <= s.delta do
      digits = round_digit(digits, s.delta, tmp, u64(div <<< s.shift), s.wfrac)
      {digits, s.k + kappa}
    else
      integral_digits(%{s | digits: digits, part1: part1, kappa: kappa, divp: s.divp + 1})
    end
  end

  defp fraction_digits(s, unit) do
    part2 = u64(s.part2 * 10)
    delta = u64(s.delta * 10)
    kappa = s.kappa - 1
    digits = push_digit(s.digits, part2 >>> s.shift)
    part2 = part2 &&& s.one - 1

    if part2 < delta do
      digits = round_digit(digits, delta, part2, s.one, u64(s.wfrac * elem(@tens, unit)))
      {digits, s.k + kappa}
    else
      fraction_digits(%{s | digits: digits, part2: part2, delta: delta, kappa: kappa}, unit - 1)
    end
  end

  # Digits are kept reversed (last digit first) until emitted.
  defp push_digit([], 0), do: []
  defp push_digit(digits, digit), do: [digit | digits]

  defp round_digit([last | rest] = digits, delta, rem, kappa, frac) do
    if rem < frac and u64(delta - rem) >= kappa and
         (u64(rem + kappa) < frac or u64(frac - rem) > u64(rem + kappa - frac)) do
      round_digit([last - 1 | rest], delta, u64(rem + kappa), kappa, frac)
    else
      digits
    end
  end

  defp u64(value), do: value &&& @mask

  # --- Layout (emit_digits) ----------------------------------------------------

  defp emit_digits(reversed, k, negative) do
    digits = reversed |> Enum.reverse() |> Enum.map_join(&Integer.to_string/1)
    ndigits = byte_size(digits)
    exp = abs(k + ndigits - 1)

    cond do
      k >= 0 and exp < 15 ->
        digits <> String.duplicate("0", k) <> ".0"

      k < 0 and (k > -7 or exp < 10) ->
        offset = ndigits - abs(k)

        if offset <= 0,
          do: "0." <> String.duplicate("0", -offset) <> digits,
          else:
            binary_part(digits, 0, offset) <> "." <> binary_part(digits, offset, ndigits - offset)

      true ->
        scientific(digits, min(ndigits, if(negative, do: 17, else: 18)), k, exp)
    end
  end

  defp scientific(digits, ndigits, k, exp) do
    mantissa =
      if ndigits > 1,
        do: binary_part(digits, 0, 1) <> "." <> binary_part(digits, 1, ndigits - 1),
        else: binary_part(digits, 0, 1)

    sign = if k + ndigits - 1 < 0, do: "-", else: "+"
    mantissa <> "e" <> sign <> Integer.to_string(exp)
  end
end
