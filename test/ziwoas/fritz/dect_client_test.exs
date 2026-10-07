defmodule Ziwoas.Fritz.DectClientTest do
  # test/fritz_dect_client_test.rb beyond the replay vectors (fritz_dect.json).
  use ExUnit.Case, async: true

  alias Ziwoas.Fritz.DectClient

  test "an MD5 challenge is answered over UTF-16LE, as Rails does" do
    md5 =
      :crypto.hash(
        :md5,
        :unicode.characters_to_binary("deadbeef-testpass", :utf8, {:utf16, :little})
      )

    assert DectClient.response("deadbeef", "testpass") ==
             "deadbeef-" <> Base.encode16(md5, case: :lower)
  end

  # AVM's worked example ("Session-IDs im FRITZ!Box Webinterface"), recomputed with
  # Ruby's OpenSSL::KDF.pbkdf2_hmac.
  test "a PBKDF2 challenge is answered with salt2 and the twice-derived hash" do
    assert DectClient.response("2$10000$5A1711$2000$5A1722", "1example!") ==
             "5A1722$1798a1672bca7c6463d6b245f82b53703b0f50813401b03e4045a5861e689adb"
  end

  test "integers parse as Ruby's Integer(string)" do
    assert DectClient.parse_integer("342000") == {:ok, 342_000}
    assert DectClient.parse_integer("-7") == {:ok, -7}
    assert DectClient.parse_integer("+1_500") == {:ok, 1500}
    assert DectClient.parse_integer("0x10") == {:ok, 16}
    assert DectClient.parse_integer("0b101") == {:ok, 5}
    assert DectClient.parse_integer("010") == {:ok, 8}
    assert DectClient.parse_integer("0") == {:ok, 0}

    for bad <- ["inval", "", "1_", "_1", "12ab", "1.5", "0x"],
        do: assert(DectClient.parse_integer(bad) == :error)
  end

  test "a timeout is a network error" do
    plug = fn conn -> Req.Test.transport_error(conn, :timeout) end
    client = DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])

    assert {:error, "network: " <> _, %DectClient{sid: nil}} = DectClient.fetch(client, "1")
  end

  test "an invalid login page reads as a missing challenge" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 200, "<html>no xml") end
    client = DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])

    assert {:error, "no challenge in auth response", _} = DectClient.fetch(client, "1")
  end
end
