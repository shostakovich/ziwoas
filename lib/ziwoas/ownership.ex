defmodule Ziwoas.Ownership do
  @moduledoc """
  Who runs each task while Rails and Phoenix share the database (ADR-0006, issue
  #158): `migration.owners` in `config/ziwoas.yml`, mirrored check for check from
  Rails' `lib/ownership.rb` (`test/vectors/ownership.json` pins both).

    * `:rails` — Rails runs the task, Phoenix does nothing (the default).
    * `:shadow` — Rails runs it; Phoenix runs it too, reads devices, writes only the
      shadow database, sends and publishes nothing.
    * `:dry_run` — the same for tasks that switch or push: Phoenix decides, logs and
      records its decisions in the shadow database, sends nothing.
    * `:phoenix` — Phoenix runs it and writes the main database; Rails skips it.

  The class of a task fixes the modes it takes: an `:ingest` reads devices or
  services and writes the database, an `:effect` switches devices or pushes out, a
  `:route` is a form that writes the database.

  Rules for every Phoenix task:

    * do nothing unless `runs?/1`;
    * write the database only inside `Ziwoas.Repo.write/2`, which picks the main or
      the shadow database by mode;
    * every device client calls `ensure_owner!/1` (or checks `may_write_devices?/1`)
      right before it sends a command, publishes to MQTT or writes a register — the
      lowest level, not the caller.
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
  @override_key {__MODULE__, :owners}
  @boot_key {__MODULE__, :boot_owners}

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
    @moduledoc """
    Phoenix was about to act for a task it does not own, or owns without holding the
    task's lease (`Ziwoas.Lease`; `lease` names who holds it).
    """
    defexception [:task, :mode, lease: false]

    @impl true
    def message(%{task: task, lease: holder}) when holder != false,
      do: "#{task}: #{holder || "nobody"} holds its lease, so Phoenix does not act for it"

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
  The owners in effect: a test override (`override/1`), else the owners the
  application booted with (`put_boot_owners/1`: the configuration's, or all
  `:rails` when it did not load), else the configuration's. Owners are read once
  per boot, like Rails; a change needs a restart.
  """
  @spec owners() :: owners
  def owners do
    (Application.get_env(:ziwoas, :ownership_process_override, false) && override_owners()) ||
      :persistent_term.get(@boot_key, nil) ||
      Config.app_config().owners
  end

  @doc """
  The owners `Ziwoas.Application` started its writers, collector and scheduler for.
  Kept for the life of the VM, so a configuration that failed at boot and loads
  later cannot hand Phoenix a task nothing was started for.
  """
  @spec put_boot_owners(owners) :: :ok
  def put_boot_owners(owners), do: :persistent_term.put(@boot_key, owners)

  @spec mode(task, owners) :: mode
  def mode(task, owners \\ owners())

  def mode(task, owners) when task in @task_names, do: Map.fetch!(owners, task)
  def mode(task, _owners), do: raise(ArgumentError, "unknown task #{inspect(task)}")

  @doc "Whether Phoenix runs the task at all (any mode but `:rails`)."
  @spec runs?(task) :: boolean
  def runs?(task), do: mode(task) != :rails

  @doc "Whether Phoenix owns the task: writes the main database, acts on devices."
  @spec owner?(task) :: boolean
  def owner?(task), do: mode(task) == :phoenix

  @doc """
  Whether a device client may send for this task: switch a plug, publish a light
  command, write a Solakon register, push to TRMNL, publish to the shared MQTT
  broker. Only as owner — never in shadow or dry run. Reading devices is no write.
  """
  @spec may_write_devices?(task) :: boolean
  def may_write_devices?(task), do: owner?(task)

  @doc """
  Whether Phoenix acts for the task right now: owns it and holds its lease
  (`Ziwoas.Lease.held?/1`). Entry points ask this to refuse gracefully.
  """
  @spec acting?(task) :: boolean
  def acting?(task), do: owner?(task) and Ziwoas.Lease.held?(task)

  @doc """
  Raises `NotOwnerError` unless Phoenix owns the task and holds its lease. Device
  clients call it before every write.
  """
  @spec ensure_owner!(task) :: :ok
  def ensure_owner!(task) do
    case mode(task) do
      :phoenix -> ensure_lease!(task)
      mode -> raise NotOwnerError, task: task, mode: mode
    end
  end

  @doc "Raises `NotOwnerError` unless Phoenix holds the task's lease (`Ziwoas.Lease`)."
  @spec ensure_lease!(task) :: :ok
  def ensure_lease!(task) do
    if Ziwoas.Lease.held?(task),
      do: :ok,
      else: raise(NotOwnerError, task: task, mode: :phoenix, lease: Ziwoas.Lease.holder(task))
  end

  @doc """
  Where the task's database writes go: `:main` as owner, `:shadow` in shadow or dry
  run. A `:rails` task writes nowhere (`NotOwnerError`).
  """
  @spec write_target(task) :: :main | :shadow
  def write_target(task) do
    case mode(task) do
      :phoenix -> :main
      mode when mode in [:shadow, :dry_run] -> :shadow
      :rails -> raise NotOwnerError, task: task, mode: :rails
    end
  end

  # --- Test support ----------------------------------------------------------

  @doc """
  Test support (`config :ziwoas, ownership_process_override: true`): the given
  modes, every other task `:rails`, for this process and the processes it starts
  (`$callers`, `$ancestors`). Not validated, so tests can reach the guards behind the checks.
  """
  @spec override(%{optional(task) => mode}) :: :ok
  def override(modes) do
    Process.put(@override_key, Map.merge(all_rails(), modes))
    :ok
  end

  @spec clear_override() :: :ok
  def clear_override do
    Process.delete(@override_key)
    :ok
  end

  defp override_owners do
    Enum.find_value([self() | Ziwoas.Repo.test_lineage()], fn
      pid when pid == self() ->
        Process.get(@override_key)

      pid ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dictionary} ->
            with {_key, owners} <- List.keyfind(dictionary, @override_key, 0), do: owners

          nil ->
            nil
        end
    end)
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
