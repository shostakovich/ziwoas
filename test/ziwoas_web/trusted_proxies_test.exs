defmodule ZiwoasWeb.TrustedProxiesTest do
  use ExUnit.Case, async: false

  alias ZiwoasWeb.TrustedProxies

  setup do
    previous = Application.get_env(:ziwoas, :trusted_proxies)
    on_exit(fn -> Application.put_env(:ziwoas, :trusted_proxies, previous) end)
  end

  defp trust(entries), do: Application.put_env(:ziwoas, :trusted_proxies, entries)

  test "an exact address trusts only itself" do
    trust(["10.0.0.5"])

    assert TrustedProxies.trusted?({10, 0, 0, 5})
    refute TrustedProxies.trusted?({10, 0, 0, 6})
  end

  test "a CIDR range trusts every address inside it" do
    trust(["172.18.0.0/16", "fd00::/8"])

    assert TrustedProxies.trusted?({172, 18, 3, 4})
    refute TrustedProxies.trusted?({172, 19, 0, 1})
    assert TrustedProxies.trusted?({0xFD12, 0, 0, 0, 0, 0, 0, 1})
    refute TrustedProxies.trusted?({0xFE80, 0, 0, 0, 0, 0, 0, 1})
  end

  test "an IPv4 peer mapped into IPv6 counts as its IPv4 address" do
    trust(["192.0.2.1"])

    assert TrustedProxies.trusted?({0, 0, 0, 0, 0, 0xFFFF, 0xC000, 0x0201})
  end

  test "without entries nothing is trusted" do
    trust([])

    refute TrustedProxies.trusted?({127, 0, 0, 1})
    refute TrustedProxies.trusted?(nil)
  end

  test "an entry that is no address or range raises" do
    for entry <- ["proxy.example.test", "10.0.0.0/33", "10.0.0.1/x", "1.2.3"] do
      trust([entry])
      assert_raise ArgumentError, fn -> TrustedProxies.entries!() end
    end
  end
end
