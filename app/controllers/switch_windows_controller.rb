# The Zeitfenster as a resource: identified by its group, never by one of the
# two rules it is made of. Pausing, editing and deleting always hit both halves,
# so a half-open state cannot be reached through this controller.
class SwitchWindowsController < ApplicationController
  include ScheduleEditing

  FORM = "switches/window_form".freeze

  def new
    render_editor(SwitchRules::WindowForm.new)
  end

  def create
    result = SwitchRules::Contracts::Window.new.call(window_attrs)
    return render_editor(form_from(result), status: :unprocessable_entity) if result.failure?

    SwitchRules::SaveWindow.call(plug_id: @plug.id, attrs: result.to_h)
    render_entries
  end

  def edit
    pair = halves
    return head :not_found unless pair

    on, off = pair
    render_row(SwitchRules::WindowForm.for_group(group_id, on: on, off: off), group_id)
  end

  def update
    return head :not_found unless halves

    result = SwitchRules::Contracts::Window.new.call(window_attrs)
    return render_row(form_from(result, group_id: group_id), group_id, status: :unprocessable_entity) if result.failure?

    SwitchRules::SaveWindow.call(plug_id: @plug.id, attrs: result.to_h, group_id: group_id)
    render_entries
  end

  # Pausing bypasses the contract on its own member route: a toggle carries one
  # boolean and no times at all.
  def enabled
    return head :not_found if group_rules.empty?

    SwitchRules::SetEnabled.call(group_rules, enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    render_entries
  end

  def destroy
    return head :not_found if group_rules.empty?

    group_rules.destroy_all
    render_entries
  end

  private

  def group_id    = params[:group_id]
  def group_rules = SwitchRule.where(plug_id: @plug.id, group_id: group_id)

  # Both halves or nothing: a group that lost one is shown and edited as an
  # Einzelschaltung, which is the other controller's business.
  def halves
    rules = group_rules.to_a
    on    = rules.find { |r| r.action == "on" }
    off   = rules.find { |r| r.action == "off" }
    [ on, off ] if on && off
  end

  def window_attrs
    attrs = params.fetch(:switch_window, {})
    { on_at_time: attrs[:on_at_time], off_at_time: attrs[:off_at_time], days: weekdays(attrs[:days]) }
  end

  # Whatever the contract could still coerce comes back into the form, so the
  # human does not lose the fields that were fine.
  def form_from(result, group_id: nil)
    SwitchRules::WindowForm.new(
      group_id: group_id, errors: error_messages(result),
      **result.to_h.slice(:on_at_time, :off_at_time, :days).compact
    )
  end
end
