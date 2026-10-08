defmodule Ziwoas.Http do
  @moduledoc false

  @stubs Application.compile_env(:ziwoas, :http_stubs, false)

  @spec new(module, keyword) :: Req.Request.t()
  def new(client, opts) do
    stubs =
      if @stubs and not Keyword.has_key?(opts, :plug),
        do: [plug: {Req.Test, client}],
        else: []

    Req.new([decode_body: false] ++ opts ++ stubs)
  end
end
