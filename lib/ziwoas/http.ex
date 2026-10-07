defmodule Ziwoas.Http do
  @moduledoc """
  Req for the outbound clients (Bright Sky, SwitchBot, TRMNL). Bodies stay raw
  (`decode_body: false`): the clients decode with Elixir's `JSON`, which keeps
  Integer and Float apart as Ruby's parser does.

  Tests route every client through `Req.Test`, stubbed under the client's module
  name (`config :ziwoas, http_stubs: true`), unless the caller passes its own
  `plug:` (the collector's clients, whose tests run them in other processes).
  """

  @spec new(module, keyword) :: Req.Request.t()
  def new(client, opts) do
    stubs =
      if Application.get_env(:ziwoas, :http_stubs, false) and not Keyword.has_key?(opts, :plug),
        do: [plug: {Req.Test, client}],
        else: []

    Req.new([decode_body: false] ++ opts ++ stubs)
  end
end
