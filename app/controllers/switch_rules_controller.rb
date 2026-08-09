# The Einzelschaltung as a resource: one rule, addressed by its own id, with an
# explicit direction. The mirror of SwitchWindowsController — same five actions,
# same member route for pausing, one record instead of a pair.
class SwitchRulesController < ApplicationController
  include ScheduleEditing

  FORM = "switches/single_form".freeze

  def new
    render_editor(SwitchRules::SingleForm.new)
  end

  def create
    result = SwitchRules::Contracts::Single.new.call(single_attrs)
    return render_editor(form_from(result), status: :unprocessable_entity) if result.failure?

    SwitchRules::SaveSingle.call(plug_id: @plug.id, attrs: result.to_h)
    render_entries
  end

  def edit
    rule = find_rule or return head :not_found
    render_row(SwitchRules::SingleForm.for_rule(rule), rule.id)
  end

  def update
    rule = find_rule or return head :not_found

    result = SwitchRules::Contracts::Single.new.call(single_attrs)
    return render_row(form_from(result, id: rule.id), rule.id, status: :unprocessable_entity) if result.failure?

    SwitchRules::SaveSingle.call(plug_id: @plug.id, attrs: result.to_h, rule: rule)
    render_entries
  end

  def enabled
    return head :not_found if rule_scope.empty?

    SwitchRules::SetEnabled.call(rule_scope, enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    render_entries
  end

  def destroy
    rule = find_rule or return head :not_found

    rule.destroy!
    render_entries
  end

  private

  # The leftover of a group that lost its partner stays reachable here: folding
  # shows it as an Einzelschaltung, and that row's buttons point at these routes.
  def rule_scope
    @rule_scope ||= begin
      scope = SwitchRule.where(plug_id: @plug.id, id: params[:id])
      scope.first&.half_of_a_window? ? SwitchRule.none : scope
    end
  end

  def find_rule = rule_scope.first

  def single_attrs
    attrs = params.fetch(:switch_rule, {})
    { at_minute_time: attrs[:at_minute_time], action: attrs[:action], days: weekdays(attrs[:days]) }
  end

  def form_from(result, id: nil)
    SwitchRules::SingleForm.new(
      id: id, errors: error_messages(result),
      **result.to_h.slice(:at_minute_time, :action, :days).compact
    )
  end
end
