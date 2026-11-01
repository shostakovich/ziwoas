defmodule Ziwoas.HueStub do
  @moduledoc """
  A Hue Bridge as a Req adapter (`req: HueStub.req(stub)`). Unlike Req's test plug it keeps the
  event stream open, so a test can push events into it or drop it.

  The test gets `{:hue, method, path}` for every request and `{:hue_put, id, body}` for every
  light update. Options shape the answers:

    * `:resources` - the resource list, or a function of the full read's number (from 1) that
      answers a list or a `{status, body}` failure
    * `:events` - a function of the event stream's number (from 1) answering the events the
      stream opens with
    * `:put` - a function of the light ID answering `{status, body}`
    * `:config` - the `{status, body}` of `/api/0/config`
  """
  use Agent

  import Ziwoas.HueFixtures

  alias Ziwoas.Config.Hue

  @stub_options [:resources, :events, :put, :config]
  @hour :timer.hours(1)

  def start_link(opts) do
    resources = Keyword.get(opts, :resources, resources())

    state = %{
      test: Keyword.fetch!(opts, :test),
      resources: if(is_function(resources), do: resources, else: fn _read -> resources end),
      events: Keyword.get(opts, :events, fn _stream -> [] end),
      put: Keyword.get(opts, :put, &updated/1),
      config: Keyword.get(opts, :config, {200, ~s({"bridgeid":"#{bridge_id()}"})}),
      reads: 0,
      streams: 0,
      stream: nil,
      requests: []
    }

    Agent.start_link(fn -> state end)
  end

  @doc "A stub and a Hue bridge on it, connected. The stub's options go to the stub, the rest to the bridge."
  def start_bridge!(opts \\ []) do
    {stub_opts, bridge_opts} = Keyword.split(opts, @stub_options)
    stub = ExUnit.Callbacks.start_supervised!({__MODULE__, [test: self()] ++ stub_opts})

    defaults = [
      hue: %Hue{host: "bridge.test", application_key: "app-key"},
      req: req(stub),
      retry_ms: @hour,
      idle_ms: @hour
    ]

    bridge =
      ExUnit.Callbacks.start_supervised!(
        {Ziwoas.Hue.Bridge, Keyword.merge(defaults, bridge_opts)}
      )

    :sys.get_state(bridge)
    {bridge, stub}
  end

  def req(stub), do: [adapter: __MODULE__, finch_private: %{hue_stub: stub}]

  @doc "Sends events down the open stream and waits until the bridge has handled them."
  def push(stub, events), do: push_raw(stub, chunk(events))

  @doc "Sends bytes down the open stream and waits until the bridge has handled them."
  def push_raw(stub, data) do
    {bridge, ref} = Agent.get(stub, & &1.stream)
    send(bridge, {ref, {:data, data}})
    :sys.get_state(bridge)
  end

  @doc "Every request so far as `{path, options}`, the options as Req hands them to its adapter."
  def requests(stub), do: stub |> Agent.get(& &1.requests) |> Enum.reverse()

  def drop(stub) do
    {bridge, ref} = Agent.get(stub, & &1.stream)
    send(bridge, {ref, :done})
    :sys.get_state(bridge)
  end

  @doc false
  def run(request) do
    stub = request.options.finch_private.hue_stub
    test = Agent.get(stub, & &1.test)
    Agent.update(stub, &%{&1 | requests: [{request.url.path, request.options} | &1.requests]})
    send(test, {:hue, request.method, request.url.path})
    {request, respond(stub, request, test)}
  end

  defp respond(stub, %{url: %{path: "/api/0/config"}}, _test),
    do: response(Agent.get(stub, & &1.config))

  defp respond(stub, %{url: %{path: "/clip/v2/resource"}}, _test) do
    case Agent.get_and_update(stub, &{&1.resources.(&1.reads + 1), %{&1 | reads: &1.reads + 1}}) do
      resources when is_list(resources) -> response({200, resource_body(resources)})
      failure -> response(failure)
    end
  end

  defp respond(stub, %{method: :put, url: %{path: "/clip/v2/resource/light/" <> id}} = req, test) do
    send(test, {:hue_put, id, req.body |> IO.iodata_to_binary() |> JSON.decode!()})
    response(Agent.get(stub, & &1.put).(id))
  end

  defp respond(stub, %{url: %{path: "/eventstream/clip/v2"}}, test) do
    {relay, ref} = {self(), make_ref()}
    bridge = hd(Process.get(:"$callers", [relay]))

    events =
      Agent.get_and_update(stub, fn state ->
        streams = state.streams + 1
        {state.events.(streams), %{state | streams: streams, stream: {bridge, ref}}}
      end)

    if events != [], do: send(bridge, {ref, {:data, event_stream(events)}})

    async = %Req.Response.Async{
      pid: bridge,
      ref: ref,
      stream_fun: fn
        ^ref, {^ref, {:data, data}} -> {:ok, [data: data]}
        ^ref, {^ref, :done} -> {:ok, [:done]}
        _ref, _message -> :unknown
      end,
      cancel_fun: fn ^ref ->
        send(test, :hue_stream_cancelled)
        Process.exit(relay, :shutdown)
        :ok
      end
    }

    Req.Response.new(status: 200, body: async)
  end

  defp response({status, body}), do: Req.Response.new(status: status, body: body)

  defp updated(id), do: {200, ~s({"data":[{"rid":"#{id}"}],"errors":[]})}

  defp chunk(events) do
    "id: " <> _ = chunk = events |> event_stream() |> String.replace_prefix(": hi\n\n", "")
    chunk
  end
end
