defmodule Ziwoas.Hue.EventsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Hue.Events

  @event ~s([{"type":"update","data":[{"id":"l1","type":"light","on":{"on":false}}]}])

  test "a complete event comes out, the greeting is none" do
    assert {[%{"type" => "update", "data" => [%{"id" => "l1"}]}], ""} =
             Events.parse(": hi\n\nid: 1:0\ndata: #{@event}\n\n")
  end

  test "an event split across chunks waits for its end" do
    {events, rest} = Events.parse("id: 1:0\ndata: " <> String.slice(@event, 0, 20))
    assert events == []

    assert {[%{"type" => "update"}], ""} =
             Events.parse(rest <> String.slice(@event, 20..-1//1) <> "\n\n")
  end

  test "CRLF line ends, several data lines and broken JSON" do
    assert {[_one, _two], ""} =
             Events.parse(~s(data: #{@event}\r\n\r\ndata: [{"type":\r\ndata: "add"}]\r\n\r\n))

    assert Events.parse("data: [{broken\n\n") == {[], ""}
    assert Events.parse(~s(data: {"type":"update"}\n\n)) == {[], ""}
  end
end
