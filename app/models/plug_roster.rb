# The configured plugs plus their roles: the one place that knows who produces
# and who consumes, and which sign a measurement carries.
class PlugRoster
  BUCKET_KEY_BY_ROLE = { producer: :production_w, consumer: :consumption_w }.freeze

  def self.wrap(plugs)
    plugs.is_a?(self) ? plugs : new(plugs)
  end

  def self.signed_watts(watt, role:)
    role == :producer ? watt.abs : watt
  end

  def initialize(plugs)
    @all         = plugs.to_a.freeze
    @by_id       = @all.index_by(&:id).freeze
    @by_role     = @all.group_by(&:role).freeze
  end

  attr_reader :all

  def ids           = @ids           ||= @all.map(&:id).freeze
  def consumers     = @by_role.fetch(:consumer, [])
  def producers     = @by_role.fetch(:producer, [])
  def consumer_ids  = @consumer_ids  ||= consumers.map(&:id).freeze
  def producer_ids  = @producer_ids  ||= producers.map(&:id).freeze

  def find(plug_id) = @by_id[plug_id]
  def role_of(plug_id) = @by_id[plug_id]&.role

  def measured?(plug_id) = BUCKET_KEY_BY_ROLE.key?(role_of(plug_id))
  def bucket_key(plug_id) = BUCKET_KEY_BY_ROLE.fetch(role_of(plug_id))

  def signed_watts(plug_id, watt) = self.class.signed_watts(watt, role: role_of(plug_id))
end
