defmodule ZiwoasWeb.TurboStream do
  @moduledoc """
  Turbo Stream responses as Rails' `render turbo_stream:` writes them: one
  `<turbo-stream>` per `{action, target, rendered}`, in order. Turbo applies
  them on the pages Rails still serves; Phoenix's own pages do without Turbo.
  """
  import Plug.Conn

  @content_type "text/vnd.turbo-stream.html"

  @spec send(Plug.Conn.t(), [{String.t(), String.t(), term}], integer) :: Plug.Conn.t()
  def send(conn, streams, status \\ 200) do
    body =
      Enum.map(streams, fn {action, target, rendered} ->
        [
          ~s(<turbo-stream action="#{action}" target="#{target}"><template>),
          Phoenix.HTML.Safe.to_iodata(rendered),
          "</template></turbo-stream>"
        ]
      end)

    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(status, body)
  end

  @doc """
  Rails' `head` inside an action: no body, the negotiated format as the content
  type — a stream when Turbo asks for one. (A `before_action`'s `head` runs before
  Rails sets the formats and always says text/html: `ScheduleEditing.head/2`.)
  """
  @spec head(Plug.Conn.t(), atom | integer) :: Plug.Conn.t()
  def head(conn, status) do
    type = if requested?(conn), do: @content_type, else: "text/html"
    conn |> put_resp_content_type(type) |> send_resp(status, "")
  end

  @doc "Renders a function component outside a template, for `send/3`."
  @spec component((map -> term), map) :: term
  def component(fun, assigns), do: fun.(Map.put(assigns, :__changed__, nil))

  @doc """
  Whether Rails' `respond_to` with `format.turbo_stream` before `format.html`
  answers a stream: the first of the two the Accept header names, by quality;
  `*/*` on its own takes the first; a browser's list with `*/*` means HTML.
  """
  @spec requested?(Plug.Conn.t()) :: boolean
  def requested?(conn) do
    accept = conn |> get_req_header("accept") |> Enum.join(",")

    cond do
      String.trim(accept) == "" -> false
      accept =~ ~r{,\s*\*/\*|\*/\*\s*,} -> false
      true -> first_known(accept) in [@content_type, "*/*"]
    end
  end

  defp first_known(accept) do
    accept
    |> String.split(",")
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      [type | params] = entry |> String.split(";") |> Enum.map(&String.trim/1)
      {String.downcase(type), quality(params), index}
    end)
    |> Enum.sort_by(fn {_type, q, index} -> {-q, index} end)
    |> Enum.find_value(fn {type, _q, _index} ->
      if type in [@content_type, "text/html", "*/*"], do: type
    end)
  end

  defp quality(params) do
    Enum.find_value(params, 1.0, fn param ->
      case String.split(param, "=", parts: 2) do
        ["q", value] -> Ziwoas.RubyNumeric.to_f(value)
        _ -> nil
      end
    end)
  end
end
