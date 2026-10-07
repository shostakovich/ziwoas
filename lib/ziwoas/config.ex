defmodule Ziwoas.Config do
  @moduledoc """
  The device configuration: `config/ziwoas.yml`. Raw YAML is cast into embedded
  schemas at this boundary, one per section; nothing downstream sees a map from
  the file. A config that does not validate is one error message listing every
  problem. Keys no schema knows are ignored (only `trmnl` refuses them).

  `Ziwoas.Application` loads the file once at boot (`load/1` on `path/0`, set
  from `ZIWOAS_CONFIG` in `config/runtime.exs`) and keeps the result with
  `put/1`. `fetch/0` answers it as `{:ok, config}` or `{:error, message}`,
  `get/0` answers the config or raises `Ziwoas.Config.Error`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ziwoas.Config.Types
  alias Ziwoas.Location
  alias Ziwoas.Plugs.{Plug, Roster}

  defmodule Error do
    defexception [:message]
  end

  defmodule FritzPoll do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    alias Ziwoas.Config.Types

    @intervals [:active_interval_seconds, :idle_interval_seconds, :timeout_seconds]

    @primary_key false
    embedded_schema do
      field :active_interval_seconds, Types.Number
      field :idle_interval_seconds, Types.Number
      field :idle_threshold_w, Types.Real
      field :timeout_seconds, Types.Number
    end

    def changeset(poll, params) do
      poll
      |> cast(params, [:idle_threshold_w | @intervals])
      |> validate_required([:idle_threshold_w | @intervals], message: "is required")
      |> then(&Enum.reduce(@intervals, &1, fn field, cs -> positive(cs, field) end))
      |> validate_number(:idle_threshold_w, greater_than_or_equal_to: 0, message: "must be >= 0")
    end

    defp positive(changeset, field),
      do: validate_number(changeset, field, greater_than: 0, message: "must be > 0")
  end

  defmodule FritzBox do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    alias Ziwoas.Config.Types

    @primary_key false
    embedded_schema do
      field :host, Types.Text
      field :user, Types.Text
      field :password, Types.Text, redact: true
    end

    def changeset(box, params) do
      box
      |> cast(params, [:host, :user, :password])
      |> validate_required([:host, :user, :password], message: "is required")
    end
  end

  defmodule Switchbot do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    alias Ziwoas.Config.Types

    @primary_key false
    embedded_schema do
      field :token, Types.Text, redact: true
      field :secret, Types.Text, redact: true
    end

    def changeset(switchbot, params) do
      switchbot
      |> cast(params, [:token, :secret])
      |> validate_required([:token, :secret], message: "is required")
    end
  end

  defmodule Sensor do
    @moduledoc "An air sensor: `type` is `:meter_pro_co2` (indoor) or `:outdoor_meter`."
    use Ecto.Schema
    import Ecto.Changeset
    alias Ziwoas.Config.Types

    @primary_key false
    embedded_schema do
      field :id, Types.Text
      field :name, Types.Text
      field :type, Ecto.Enum, values: [:meter_pro_co2, :outdoor_meter]
      field :room, Types.Text
    end

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            type: :meter_pro_co2 | :outdoor_meter,
            room: String.t() | nil
          }

    @doc false
    def changeset(sensor, params) do
      sensor
      |> cast(params, [:id, :name, :type, :room], message: &Types.cast_message/2)
      |> validate_required([:id, :name, :type], message: "is required")
    end
  end

  defmodule Trmnl do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    alias Ziwoas.Config.Types

    @urls [:energy_webhook_url, :sensors_webhook_url]

    @primary_key false
    embedded_schema do
      field :energy_webhook_url, :string
      field :sensors_webhook_url, :string
    end

    def changeset(trmnl, params) do
      trmnl
      |> cast(params, @urls, message: &Types.cast_message/2)
      |> validate_known_keys(params)
    end

    defp validate_known_keys(changeset, params) do
      case Map.keys(params) -- Enum.map(@urls, &Atom.to_string/1) do
        [] -> changeset
        unknown -> add_error(changeset, :base, "trmnl unknown keys: #{Enum.join(unknown, ", ")}")
      end
    end
  end

  defmodule Solakon do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    alias Ziwoas.Config.Types

    @primary_key false
    embedded_schema do
      field :host, Types.Text
      field :port, Types.Count, default: 502
      field :unit_id, Types.Count, default: 1
      field :monitoring_enabled, Types.Flag, default: true
      field :control_enabled, Types.Flag, default: false
    end

    def changeset(solakon, params) do
      solakon
      |> cast(params, [:host, :port, :unit_id, :monitoring_enabled, :control_enabled])
      |> validate_required([:host], message: "is required")
      |> validate_number(:port, greater_than: 0, message: "must be > 0")
      |> validate_number(:unit_id, greater_than_or_equal_to: 0, message: "must be >= 0")
    end
  end

  defmodule Govee do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    alias Ziwoas.Config.Types

    @intervals [:lan_poll_seconds, :api_poll_seconds, :pending_window_seconds]

    @primary_key false
    embedded_schema do
      field :api_key, Types.Text, redact: true
      field :lan_poll_seconds, Types.Count, default: 8
      field :api_poll_seconds, Types.Count, default: 180
      field :pending_window_seconds, Types.Count, default: 5
      # Display names by device key, from `devices`.
      field :names, :map, default: %{}

      embeds_many :devices, Device, primary_key: false do
        field :key, Types.Text
        field :name, Types.Text
      end
    end

    def changeset(govee, params) do
      govee
      |> cast(params, [:api_key | @intervals])
      |> then(&Enum.reduce(@intervals, &1, fn field, cs -> positive(cs, field) end))
      |> cast_embed(:devices,
        with: &device_changeset/2,
        invalid_message: "must be a list of mappings"
      )
      |> put_names()
    end

    defp positive(changeset, field),
      do: validate_number(changeset, field, greater_than: 0, message: "must be > 0")

    defp device_changeset(device, params) do
      device
      |> cast(params, [:key, :name])
      |> validate_required([:key], message: "is required")
    end

    defp put_names(changeset) do
      if changeset.valid? do
        names = Map.new(get_field(changeset, :devices), &{&1.key, %{name: &1.name || ""}})
        put_change(changeset, :names, names)
      else
        changeset
      end
    end
  end

  @primary_key false
  embedded_schema do
    embeds_one :location, Location
    embeds_one :fritz_poll, FritzPoll
    embeds_one :fritz_box, FritzBox
    embeds_many :plugs, Plug
    embeds_one :switchbot, Switchbot
    embeds_many :sensors, Sensor
    embeds_one :trmnl, Trmnl
    embeds_one :solakon, Solakon
    embeds_one :govee, Govee
  end

  @type t :: %__MODULE__{
          location: Location.t(),
          fritz_poll: %FritzPoll{} | nil,
          plugs: [Plug.t()],
          fritz_box: %FritzBox{} | nil,
          switchbot: %Switchbot{} | nil,
          sensors: [Sensor.t()],
          trmnl: %Trmnl{},
          solakon: %Solakon{} | nil,
          govee: %Govee{} | nil
        }

  # --- The loaded configuration --------------------------------------------------

  @doc "The configuration loaded at boot: `{:ok, config}` or `{:error, message}`."
  @spec fetch() :: {:ok, t} | {:error, String.t()}
  def fetch, do: :persistent_term.get(__MODULE__, {:error, "config not loaded"})

  @doc "The configuration loaded at boot; raises `Ziwoas.Config.Error` with its error."
  @spec get() :: t
  def get do
    case fetch() do
      {:ok, config} -> config
      {:error, message} -> raise Error, message
    end
  end

  @doc "Keeps a load result for `fetch/0` and `get/0`."
  @spec put({:ok, t} | {:error, String.t()}) :: :ok
  def put({:ok, %__MODULE__{}} = result), do: :persistent_term.put(__MODULE__, result)

  def put({:error, message} = result) when is_binary(message),
    do: :persistent_term.put(__MODULE__, result)

  @doc "The path of the device config (`config :ziwoas, :config_path`)."
  @spec path() :: String.t()
  def path, do: Application.fetch_env!(:ziwoas, :config_path)

  @spec plug_roster(t) :: Roster.t()
  def plug_roster(%__MODULE__{plugs: plugs}), do: Roster.new(plugs)

  # --- Loading ---------------------------------------------------------------------

  @doc "Reads and validates the config file at `path`."
  @spec load(String.t()) :: {:ok, t} | {:error, String.t()}
  def load(path) do
    if File.regular?(path),
      do: with({:ok, raw} <- parse_file(path), do: build(raw)),
      else: {:error, "config file not found: #{path}"}
  end

  @doc "Validates a configuration given as YAML text."
  @spec from_yaml(String.t()) :: {:ok, t} | {:error, String.t()}
  def from_yaml(yaml), do: with({:ok, raw} <- parse_string(yaml), do: build(raw))

  @doc "`from_yaml/1`, raising `Ziwoas.Config.Error`."
  @spec from_yaml!(String.t()) :: t
  def from_yaml!(yaml) do
    case from_yaml(yaml) do
      {:ok, config} -> config
      {:error, message} -> raise Error, message
    end
  end

  defp parse_file(path),
    do: parse(fn opts -> :yamerl_constr.file(String.to_charlist(path), opts) end)

  defp parse_string(yaml), do: parse(fn opts -> :yamerl_constr.string(yaml, opts) end)

  # YAML 1.1: unquoted yes/no/on/off (and y/n) are booleans.
  @yaml_opts [
    :str_node_as_binary,
    {:map_node_format, :map},
    {:node_mods, [:yamerl_node_bool_ext]}
  ]

  defp parse(fun) do
    case fun.(@yaml_opts) do
      [document | _] -> {:ok, normalize(document)}
      [] -> {:ok, nil}
    end
  catch
    {:yamerl_exception, _errors} -> {:error, "config file is not valid YAML"}
  end

  # YAML's null is `:null`; a key without a value counts as absent.
  defp normalize(map) when is_map(map),
    do:
      for({key, value} <- map, value not in [nil, :null], into: %{}, do: {key, normalize(value)})

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value

  defp build(raw) when is_map(raw) do
    case apply_action(changeset(raw), :load) do
      {:ok, config} -> {:ok, config}
      {:error, changeset} -> {:error, error_message(changeset)}
    end
  end

  defp build(_raw), do: {:error, "config root must be a mapping"}

  # --- Validation ------------------------------------------------------------------

  defp changeset(raw) do
    params = raw |> Map.put_new("trmnl", %{}) |> list_govee_devices()

    %__MODULE__{}
    |> cast(params, [])
    |> cast_embed(:location,
      required: true,
      required_message: "is required",
      invalid_message: "must be a mapping"
    )
    |> cast_embed(:fritz_poll, invalid_message: "must be a mapping")
    |> cast_embed(:fritz_box, invalid_message: "must be a mapping")
    |> cast_embed(:plugs, invalid_message: "must be a list of mappings")
    |> cast_embed(:switchbot, invalid_message: "must be a mapping")
    |> cast_embed(:sensors,
      with: &Sensor.changeset/2,
      invalid_message: "must be a list of mappings"
    )
    |> cast_embed(:trmnl, invalid_message: "must be a mapping")
    |> cast_embed(:solakon, invalid_message: "must be a mapping")
    |> cast_embed(:govee, invalid_message: "must be a mapping")
    |> validate_plugs_given(raw)
    |> validate_unique(:plugs, "plug")
    |> validate_unique(:sensors, "sensor")
    |> validate_producer()
    |> validate_fritz()
  end

  # A single device reads as a list of one.
  defp list_govee_devices(%{"govee" => %{"devices" => %{} = device}} = raw),
    do: put_in(raw, ["govee", "devices"], [device])

  defp list_govee_devices(raw), do: raw

  # Required, but may be empty, which `cast_embed/3`'s `required:` refuses.
  defp validate_plugs_given(changeset, raw) do
    if Map.has_key?(raw, "plugs"),
      do: changeset,
      else: add_error(changeset, :plugs, "must be a list")
  end

  defp validate_unique(changeset, field, noun) do
    changeset
    |> embedded(field)
    |> Enum.map(& &1.id)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.reduce(changeset, fn {id, _}, changeset ->
      add_error(changeset, :base, "duplicate #{noun} id '#{id}'")
    end)
  end

  defp validate_producer(changeset) do
    roles = changeset |> embedded(:plugs) |> Enum.map(& &1.role)

    if roles != [] and :producer not in roles and nil not in roles,
      do:
        add_error(changeset, :base, "config must include at least one plug with role: producer"),
      else: changeset
  end

  defp validate_fritz(changeset) do
    if Enum.any?(embedded(changeset, :plugs), &(&1.driver == :fritz_dect)),
      do: Enum.reduce([:fritz_box, :fritz_poll], changeset, &require_fritz_section/2),
      else: changeset
  end

  defp require_fritz_section(section, changeset) do
    if get_field(changeset, section),
      do: changeset,
      else:
        add_error(changeset, :base, "#{section} config required when using driver: fritz_dect")
  end

  # The embedded entries as cast so far, valid or not.
  defp embedded(changeset, field) do
    case get_change(changeset, field) do
      changesets when is_list(changesets) -> Enum.map(changesets, &apply_changes/1)
      nil -> []
    end
  end

  # --- Error message ----------------------------------------------------------------

  defp error_message(changeset) do
    changeset
    |> traverse_errors(&interpolate/1)
    |> flatten([])
    |> Enum.join("; ")
  end

  defp interpolate({message, opts}) do
    Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end

  defp flatten(errors, path) when is_map(errors),
    do: Enum.flat_map(errors, fn {key, value} -> flatten(value, path ++ [key]) end)

  defp flatten(errors, path) when is_list(errors) do
    errors
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {message, _index} when is_binary(message) -> [line(path, message)]
      {nested, index} -> flatten(nested, path ++ [index])
    end)
  end

  defp line(path, message) do
    case List.delete(path, :base) do
      ^path -> render_path(path) <> " " <> message
      _ -> message
    end
  end

  defp render_path(path) do
    Enum.reduce(path, "", fn
      index, text when is_integer(index) -> text <> "[#{index}]"
      key, "" -> Atom.to_string(key)
      key, text -> text <> "." <> Atom.to_string(key)
    end)
  end
end
