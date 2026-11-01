defmodule Ziwoas.Hue.ClientTest do
  use ExUnit.Case, async: true

  import Ziwoas.HueFixtures

  alias Ziwoas.Hue.Client
  alias Ziwoas.HueStub

  @key "app-key"

  defp client(respond) do
    test = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      key = conn |> Plug.Conn.get_req_header("hue-application-key") |> List.first()
      send(test, {:hue, conn.method, conn.request_path, key, body})
      {status, response} = respond.(conn.method, conn.request_path)
      Plug.Conn.send_resp(conn, status, response)
    end

    %{Client.new("bridge.test", @key, plug: plug) | bridge_id: String.downcase(bridge_id())}
  end

  test "identifies the bridge without sending the key" do
    client = client(fn "GET", "/api/0/config" -> {200, ~s({"bridgeid":"#{bridge_id()}"})} end)

    assert {:ok, %Client{bridge_id: "001788fffe6a1b2c"}} =
             Client.identify(%{client | bridge_id: nil})

    assert_received {:hue, "GET", "/api/0/config", nil, ""}
  end

  test "an answer without a bridge ID is no bridge" do
    client = client(fn _method, _path -> {200, ~s({"name":"something"})} end)
    assert Client.identify(client) == {:error, :invalid_json}
  end

  test "reads the resources with the key" do
    client = client(fn "GET", "/clip/v2/resource" -> {200, resource_body()} end)

    assert {:ok, resources} = Client.resources(client)
    assert length(resources) == length(resources())
    assert_received {:hue, "GET", "/clip/v2/resource", @key, ""}
  end

  test "updates a light and passes on what the bridge refuses" do
    client =
      client(fn
        "PUT", "/clip/v2/resource/light/l1" ->
          {200, ~s({"data":[{"rid":"l1"}],"errors":[]})}

        "PUT", "/clip/v2/resource/light/l2" ->
          {207, ~s({"data":[],"errors":[{"description":"nope"}]})}

        "PUT", "/clip/v2/resource/light/l3" ->
          {404, ~s({"data":[],"errors":[{"description":"gone"}]})}

        "PUT", "/clip/v2/resource/light/l4" ->
          {503, "busy"}
      end)

    assert Client.update_light(client, "l1", %{"on" => %{"on" => true}}) == :ok
    assert_received {:hue, "PUT", "/clip/v2/resource/light/l1", @key, ~s({"on":{"on":true}})}

    assert Client.update_light(client, "l2", %{}) == {:error, {:hue, ["nope"]}}
    assert Client.update_light(client, "l3", %{}) == {:error, {:hue, ["gone"]}}
    assert Client.update_light(client, "l4", %{}) == {:error, {:http_status, 503}}
  end

  test "an answer that is not JSON, or has no data" do
    assert Client.resources(client(fn _, _ -> {200, "<html>"} end)) == {:error, :invalid_json}
    assert Client.resources(client(fn _, _ -> {200, "{}"} end)) == {:error, :invalid_json}
  end

  test "opens the event stream, whose chunks come as messages" do
    client = client(fn "GET", "/eventstream/clip/v2" -> {200, ": hi\n\n"} end)

    assert {:ok, stream} = Client.open_events(client)
    assert_receive {:hue, "GET", "/eventstream/clip/v2", @key, ""}
    assert_receive message
    assert Req.parse_message(stream, message) == {:ok, [data: ": hi\n\n"]}
  end

  test "an event stream whose answer never comes is given up" do
    test = self()

    plug = fn _conn ->
      send(test, {:waiting, self()})
      Process.sleep(:infinity)
    end

    client = %{Client.new("bridge.test", @key, plug: plug) | bridge_id: "id", open_timeout_ms: 50}

    assert Client.open_events(client) == {:error, :timeout}
    assert_received {:waiting, request}
    refute Process.alive?(request)
  end

  test "a refused event stream is an error" do
    client = client(fn _method, _path -> {403, "forbidden"} end)
    assert Client.open_events(client) == {:error, {:http_status, 403}}
  end

  test "checks the bridge against the Hue root CA alone, keyed requests also against its ID" do
    stub = start_supervised!({HueStub, test: self()})
    {:ok, client} = Client.identify(Client.new("bridge.test", @key, HueStub.req(stub)))
    {:ok, _resources} = Client.resources(client)
    :ok = Client.update_light(client, candle(), %{})
    {:ok, _stream} = Client.open_events(client)

    assert [
             {"/api/0/config", identify},
             {"/clip/v2/resource", resources},
             {"/clip/v2/resource/light/" <> _id, update},
             {"/eventstream/clip/v2", events}
           ] = HueStub.requests(stub)

    assert transport(identify) == tls(:any)

    for keyed <- [resources, update, events],
        do: assert(transport(keyed) == tls("001788fffe6a1b2c"))
  end

  test "a light update gives up within 3 s" do
    stub = start_supervised!({HueStub, test: self()})
    client = %{Client.new("bridge.test", @key, HueStub.req(stub)) | bridge_id: "id"}
    :ok = Client.update_light(client, candle(), %{})

    assert [{_path, options}] = HueStub.requests(stub)
    assert options.connect_options[:timeout] + options.receive_timeout <= 3_000
  end

  defp transport(options), do: options.connect_options[:transport_opts]

  defp tls(peer) do
    [{:Certificate, root_ca, :not_encrypted}] =
      Path.expand("../../../priv/hue/root-bridge.pem", __DIR__)
      |> File.read!()
      |> :public_key.pem_decode()

    [
      verify: :verify_peer,
      cacerts: [root_ca],
      server_name_indication: :disable,
      reuse_sessions: false,
      verify_fun: {&Client.verify_peer/3, peer}
    ]
  end

  describe "the peer check" do
    setup do
      %{cert: certificate(~c"001788fffe6a1b2c")}
    end

    test "takes only the bridge ID as the leaf's common name", %{cert: cert} do
      assert Client.verify_peer(cert, :valid_peer, "001788fffe6a1b2c") ==
               {:valid, "001788fffe6a1b2c"}

      assert Client.verify_peer(cert, :valid_peer, "001788fffe6a1b2d") ==
               {:fail, :bridge_id_mismatch}

      assert Client.verify_peer(cert, :valid_peer, :any) == {:valid, :any}
    end

    test "fails a certificate the chain refuses and passes the rest on", %{cert: cert} do
      assert Client.verify_peer(cert, {:bad_cert, :unknown_ca}, :any) ==
               {:fail, {:bad_cert, :unknown_ca}}

      assert Client.verify_peer(cert, {:extension, :x}, "id") == {:unknown, "id"}
      assert Client.verify_peer(cert, :valid, "id") == {:valid, "id"}
    end
  end

  test "matches the bridge ID whatever its case, in the answer and in the certificate" do
    client = client(fn "GET", "/api/0/config" -> {200, ~s({"bridgeid":"001788FFFE6a1b2c"})} end)
    {:ok, %Client{bridge_id: id}} = Client.identify(%{client | bridge_id: nil})

    assert Client.verify_peer(certificate(~c"001788fffe6A1B2C"), :valid_peer, id) == {:valid, id}
  end

  defp certificate(common_name) do
    %{cert: der} = :public_key.pkix_test_root_cert(common_name, [])
    :public_key.pkix_decode_cert(der, :otp)
  end

  test "never shows the key" do
    refute inspect(Client.new("bridge.test", @key)) =~ @key
  end
end
