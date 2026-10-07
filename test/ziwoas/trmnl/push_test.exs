defmodule Ziwoas.Trmnl.PushTest do
  # test/jobs/trmnl_push_job_test.rb and trmnl_sensor_push_job_test.rb
  use Ziwoas.DataCase

  import ExUnit.CaptureLog

  alias Ziwoas.{RubyJSON, TestConfigs}
  alias Ziwoas.Trmnl.{EnergyPushJob, Push}
  alias Ziwoas.Trmnl.Push.PayloadTooLarge

  @payload [{"merge_variables", [{"ts", 1}, {"pv_kwh", 0}]}]

  defp stub_trmnl(status \\ 200) do
    test = self()

    Req.Test.stub(Push, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:posted, conn.method,
         URI.to_string(%URI{scheme: "#{conn.scheme}", host: conn.host, path: conn.request_path}),
         Plug.Conn.get_req_header(conn, "content-type"), body}
      )

      Plug.Conn.send_resp(conn, status, "")
    end)
  end

  test "without a webhook URL nothing is built or sent" do
    Req.Test.stub(Push, fn _conn -> flunk("posted") end)

    for url <- [nil, ""] do
      assert Push.run(:trmnl_push, :energy, url, fn -> flunk("built") end) == :skipped
    end
  end

  test "POSTs the payload as Rails' JSON to the URL" do
    stub_trmnl()

    assert Push.run(:trmnl_push, :energy, "https://trmnl.com/api/custom_plugins/abc", fn ->
             @payload
           end) ==
             :ok

    assert_received {:posted, "POST", "https://trmnl.com/api/custom_plugins/abc",
                     ["application/json"], body}

    assert body == RubyJSON.encode!(@payload)
  end

  test "a payload over 2 kB raises" do
    huge = [{"merge_variables", [{"blob", String.duplicate("x", 4000)}]}]

    assert_raise PayloadTooLarge, ~r/TRMNL sensor payload is \d+ B, exceeds 2048 B limit/, fn ->
      Push.run(:trmnl_push, :sensors, "https://example/", fn -> huge end)
    end
  end

  test "a failed POST is a warning" do
    Req.Test.stub(Push, &Req.Test.transport_error(&1, :econnrefused))

    log =
      capture_log(fn ->
        assert Push.run(:trmnl_push, :sensors, "https://example/", fn -> @payload end) == :failed
      end)

    assert log =~ "TRMNL sensor push errored"
    assert log =~ "connection refused"
  end

  test "an HTTP error is a warning with Rails' wording" do
    stub_trmnl(500)

    assert capture_log(fn ->
             Push.run(:trmnl_push, :energy, "https://example/", fn -> @payload end)
           end) =~
             "TRMNL push failed: HTTP 500 Internal Server Error"
  end

  test "EnergyPushJob pushes the energy widget to its webhook" do
    Ziwoas.TestClock.freeze("2026-10-05T12:00:00+02:00")
    stub_trmnl()
    config = TestConfigs.plugs("trmnl:\n  energy_webhook_url: https://example.test/energy\n")

    EnergyPushJob.perform(%{task: :trmnl_push, mode: :phoenix, config: config})

    assert_received {:posted, "POST", "https://example.test/energy", _, body}
    assert %{"merge_variables" => %{"stand" => "12:00", "pv_kwh" => +0.0}} = JSON.decode!(body)
  end
end
