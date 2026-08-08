# What SwitchWindowsController and SwitchRulesController share: the plug in the
# URL, and the Turbo targets they write back into. The two controllers differ
# only in what a row *is* — a group or a single rule — so everything around that
# lives here once.
module ScheduleEditing
  extend ActiveSupport::Concern

  included do
    before_action :set_plug
  end

  private

  def set_plug
    @plug = app_config.plugs.find { |p| p.id == params[:plug_id] }
    return head :not_found unless @plug
    head :unprocessable_entity unless @plug.switchable
  end

  def editor_id = "sw_editor_#{@plug.id}"

  # The row of a Zeitfenster is named by its group, the row of an
  # Einzelschaltung by its rule id — dom_id no longer carries, because a window
  # is not a single record.
  def entry_id(id) = "sw_entry_#{@plug.id}_#{id}"

  # Re-render the rules, the summary AND the head: the count above the list is
  # one Schaltzeit off otherwise, and the next edge in the status line may have
  # moved.
  def render_entries
    row = SwitchRow.build(@plug)
    render turbo_stream: [
      turbo_stream.replace("sw_rules_#{@plug.id}",
                           partial: "switches/entries",
                           locals: { plug: @plug, entries: row.entries }),
      turbo_stream.replace("sw_count_#{@plug.id}",
                           partial: "switches/summary", locals: { row: row }),
      turbo_stream.replace("sw_head_#{@plug.id}",
                           partial: "switches/head", locals: { row: row })
    ]
  end

  # Weekday checkboxes ship a blank first value so that unticking them all still
  # sends the key; the contract wants integers and nothing else.
  def weekdays(raw) = Array(raw).reject(&:blank?)

  def error_messages(result) = result.errors.map(&:text).uniq

  # A new entry is composed in the editor slot below the list; an existing one
  # turns into the form in place, where its row was. Both render the including
  # controller's FORM.
  def render_editor(form, status: :ok)
    render turbo_stream: turbo_stream.update(editor_id, partial: self.class::FORM, locals: form_locals(form)),
           status: status
  end

  def render_row(form, id, status: :ok)
    render turbo_stream: turbo_stream.replace(entry_id(id), partial: self.class::FORM, locals: form_locals(form)),
           status: status
  end

  def form_locals(form) = { plug: @plug, form: form }
end
