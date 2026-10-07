defmodule ZiwoasWeb.NotFoundError do
  @moduledoc "A record the URL names does not exist: 404."
  defexception message: "not found", plug_status: 404
end
