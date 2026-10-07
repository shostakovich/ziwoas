defmodule ZiwoasWeb.TurboCase do
  @moduledoc "Helpers for Turbo Stream responses in controller tests."
  import Phoenix.ConnTest

  @doc "The streams' contents as one fragment (lexbor keeps a `<template>`'s children apart)."
  def stream_doc(body) do
    body
    |> String.replace(~r{</?(turbo-stream|template)[^>]*>}, "")
    |> LazyHTML.from_fragment()
  end

  @doc "`[{action, target}]` of every `<turbo-stream>` in order."
  def streams(body) do
    for [_, action, target] <-
          Regex.scan(~r/<turbo-stream action="([^"]+)" target="([^"]+)">/, body),
        do: {action, target}
  end

  def turbo(conn),
    do: Plug.Conn.put_req_header(conn, "accept", "text/vnd.turbo-stream.html, text/html")

  def count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  def stream_response(conn, status) do
    body = response(conn, status)
    [type | _] = Plug.Conn.get_resp_header(conn, "content-type")

    if not String.starts_with?(type, "text/vnd.turbo-stream.html"),
      do: raise("not a stream: #{type}")

    body
  end
end
