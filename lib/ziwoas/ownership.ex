defmodule Ziwoas.Ownership do
  @moduledoc """
  The task table from the time Rails and Phoenix shared the database (ADR-0006).
  Phoenix now owns every task (`owners/0`); the modes other than `:phoenix` survive
  only until their branches are gone from the jobs, the collector and the scheduler.

    * `:rails` — Rails ran the task, Phoenix did nothing.
    * `:shadow` — Phoenix ran it beside Rails, read devices, sent nothing.
    * `:dry_run` — the same for tasks that switch or push: decide and log, send nothing.
    * `:phoenix` — Phoenix runs it and writes the database.

  The class of a task fixes the modes it takes: an `:ingest` reads devices or
  services and writes the database, an `:effect` switches devices or pushes out, a
  `:route` is a form that writes the database. `parse!/1` still reads the
  `migration` section of `config/ziwoas.yml`.
  """
  alias Ziwoas.Config

  @tasks [
    aggregator: :ingest,
    weather: :ingest,
    sensor_poll: :ingest,
    solakon_monitor: :ingest,
    plug_ingest: :ingest,
    light_ingest: :ingest,
    fritz_bridge: :ingest,
    govee_bridge: :ingest,
    trmnl_push: :effect,
    switching: :effect,
    lights: :effect,
    solakon_control: :effect,
    economics: :route,
    switch_schedule: :route,
    light_settings: :route
  ]

  @modes %{
    ingest: [:rails, :shadow, :phoenix],
    effect: [:rails, :dry_run, :phoenix],
    route: [:rails, :phoenix]
  }

  @task_names Keyword.keys(@tasks)

  @type task ::
          :aggregator
          | :weather
          | :sensor_poll
          | :solakon_monitor
          | :plug_ingest
          | :light_ingest
          | :fritz_bridge
          | :govee_bridge
          | :trmnl_push
          | :switching
          | :lights
          | :solakon_control
          | :economics
          | :switch_schedule
          | :light_settings
  @type mode :: :rails | :shadow | :dry_run | :phoenix
  @type owners :: %{task => mode}

  defmodule NotOwnerError do
    @moduledoc "Phoenix was about to act for a task it does not own."
    defexception [:task, :mode]

    @impl true
    def message(%{task: task, mode: mode}),
      do: "#{task} runs in #{mode} mode here: Phoenix does not own it"
  end

  @doc "Every task with its class, in table order."
  @spec tasks() :: [{task, :ingest | :effect | :route}]
  def tasks, do: @tasks

  @doc "The modes each class of task takes."
  def modes, do: @modes

  @spec all_rails() :: owners
  def all_rails, do: Map.new(@task_names, &{&1, :rails})

  # --- Asking ----------------------------------------------------------------

  @doc """
  The owners in effect: Phoenix owns every task. The `migration` section of the
  configuration is still parsed (`parse!/1`), but no longer decides anything.
  """
  @spec owners() :: owners
  def owners, do: Map.new(@task_names, &{&1, :phoenix})

  @spec mode(task, owners) :: mode
  def mode(task, owners \\ owners())

  def mode(task, owners) when task in @task_names, do: Map.fetch!(owners, task)
  def mode(task, _owners), do: raise(ArgumentError, "unknown task #{inspect(task)}")

  @doc "Whether Phoenix runs the task at all (any mode but `:rails`)."
  @spec runs?(task) :: boolean
  def runs?(task), do: mode(task) != :rails

  @doc "Whether Phoenix owns the task: writes the database, acts on devices."
  @spec owner?(task) :: boolean
  def owner?(task), do: mode(task) == :phoenix

  @doc """
  Whether a device client may send for this task: switch a plug, publish a light
  command, write a Solakon register, push to TRMNL, publish to the MQTT broker.
  Only as owner. Reading devices is no write.
  """
  @spec may_write_devices?(task) :: boolean
  def may_write_devices?(task), do: owner?(task)

  @doc "Whether Phoenix acts for the task right now. Entry points ask this to refuse gracefully."
  @spec acting?(task) :: boolean
  def acting?(task), do: owner?(task)

  @doc "Raises `NotOwnerError` unless Phoenix owns the task. Device clients call it before every write."
  @spec ensure_owner!(task) :: :ok
  def ensure_owner!(task) do
    case mode(task) do
      :phoenix -> :ok
      mode -> raise NotOwnerError, task: task, mode: mode
    end
  end

  # --- Parsing (Ownership.parse) ---------------------------------------------

  @doc "Builds the owners from the raw `migration` section; problems raise `Ziwoas.Config.Error`."
  @spec parse!(term) :: owners
  def parse!(raw) when raw in [nil, :null], do: all_rails()

  def parse!(raw) when is_map(raw) do
    unknown = raw |> Map.keys() |> Enum.map(&to_s/1) |> Kernel.--(["owners"])
    if unknown != [], do: error!("migration unknown keys: #{Enum.join(Enum.sort(unknown), ", ")}")

    raw |> Map.get("owners") |> parse_owners() |> check_pairs()
  end

  def parse!(_raw), do: error!("migration must be a mapping")

  defp parse_owners(raw) when raw in [nil, :null], do: parse_owners(%{})

  defp parse_owners(raw) when is_map(raw) do
    given = Map.new(raw, fn {task, mode} -> {to_s(task), mode} end)
    unknown = Map.keys(given) -- Enum.map(@task_names, &Atom.to_string/1)

    if unknown != [],
      do: error!("migration.owners unknown tasks: #{Enum.join(Enum.sort(unknown), ", ")}")

    Map.new(@tasks, fn {task, kind} ->
      {task, parse_mode(task, kind, Map.get(given, Atom.to_string(task), "rails"))}
    end)
  end

  defp parse_owners(_raw), do: error!("migration.owners must be a mapping")

  # Map.new walks @tasks in order, so the first bad mode in table order is reported.
  defp parse_mode(task, kind, value) do
    allowed = Map.fetch!(@modes, kind)

    Enum.find(allowed, &(is_binary(value) and Atom.to_string(&1) == value)) ||
      error!("migration.owners.#{task} must be one of #{Enum.join(allowed, ", ")}")
  end

  # Tasks that change hands together: Rails' control tick runs inside its monitor
  # job, Phoenix's on its own readings; /switches and /lights/:key carry the plug
  # knobs, the schedule editors, the lamp commands and the settings sheet, and a
  # Phoenix lamp page hears of the lamps only from Phoenix's own subscriber.
  @together [
    [:solakon_control, :solakon_monitor],
    [:switching, :lights, :switch_schedule, :light_settings, :light_ingest]
  ]

  defp check_pairs(owners) do
    for tasks <- @together, Enum.uniq_by(tasks, &(owners[&1] == :phoenix)) |> length() > 1 do
      {init, [last]} = Enum.split(tasks, -1)
      error!("migration.owners.#{Enum.join(init, ", ")} and #{last} move to phoenix together")
    end

    # A dry run of the control ticks on the readings of a shadowing monitor.
    if owners.solakon_control == :dry_run and owners.solakon_monitor != :shadow,
      do: error!("migration.owners.solakon_control: dry_run needs solakon_monitor: shadow")

    owners
  end

  defp to_s(value) when is_binary(value), do: value
  defp to_s(value) when value in [nil, :null], do: ""
  defp to_s(value) when is_atom(value), do: Atom.to_string(value)
  defp to_s(value) when is_integer(value), do: Integer.to_string(value)
  defp to_s(value) when is_float(value), do: Float.to_string(value)
  defp to_s(value), do: inspect(value)

  defp error!(message), do: raise(Config.Error, message)
end
