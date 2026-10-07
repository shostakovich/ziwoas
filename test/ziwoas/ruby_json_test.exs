defmodule Ziwoas.RubyJSONTest do
  use ExUnit.Case, async: true

  alias Ziwoas.RubyJSON

  test "pair lists are objects in their order, maps are sorted" do
    assert RubyJSON.encode!([{"b", 1}, {"a", [2, 3]}]) == ~s({"b":1,"a":[2,3]})
    assert RubyJSON.encode!(%{b: 1, a: 2}) == ~s({"a":2,"b":1})
    assert RubyJSON.encode!(%{}) == "{}"
    assert RubyJSON.encode!([]) == "[]"
  end

  test "atoms are strings, nil is null, non-finite floats are null" do
    assert RubyJSON.encode!([:producer, nil, true, false, :nan, :infinity]) ==
             ~s(["producer",null,true,false,null,null])
  end

  test "integers stay integers and floats keep their .0" do
    assert RubyJSON.encode!([0, 0.0, -0.0, 144]) == "[0,0.0,-0.0,144]"
  end

  test "dates are ISO strings" do
    assert RubyJSON.encode!(~D[2026-10-05]) == ~s("2026-10-05")
  end

  test "generate! is JSON.generate: no HTML-entity escaping, the rest as encode!" do
    value = [{"scene", "Rock & <Roll> \"x\"\n/ü"}, {"n", [1, 2.5]}]

    assert RubyJSON.generate!(value) == ~s({"scene":"Rock & <Roll> \\"x\\"\\n/ü","n":[1,2.5]})

    assert RubyJSON.encode!(value) ==
             ~s({"scene":"Rock \\u0026 \\u003cRoll\\u003e \\"x\\"\\n/ü","n":[1,2.5]})
  end
end
