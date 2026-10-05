module SwitchesHelper
  DAY_ABBR = { 1 => "Mo", 2 => "Di", 3 => "Mi", 4 => "Do", 5 => "Fr", 6 => "Sa", 7 => "So" }.freeze
  SOURCE_LABEL = { "manual" => "manuell", "schedule" => "Zeitplan" }.freeze

  def weekday_label(days)
    sorted = days.sort
    return "täglich" if sorted == Switching::Rule::ISO_DAYS
    sorted.slice_when { |a, b| b != a + 1 }
          .map { |group| group.size >= 2 ? "#{DAY_ABBR[group.first]}–#{DAY_ABBR[group.last]}" : DAY_ABBR[group.first] }
          .join(", ")
  end

  # A window's days come from its on rule, which reads a shift past midnight back out (Di–Sa → Mo–Fr).
  def entry_label(entry)
    "#{weekday_label(entry.days)} · #{entry.rules.map(&:at_minute_time).join('–')}"
  end

  def switch_status_line(row)
    return offline_line(row) if row.offline?

    state_word = row.on? ? "An" : "Aus"
    cmd        = row.last_command
    first_part =
      if cmd && (cmd.action == "on") == row.on?
        "#{state_word} seit #{cmd.created_at.strftime('%H:%M')} (#{SOURCE_LABEL[cmd.source]})"
      else
        state_word
      end
    [ first_part, schedule_part(row) ].join(" · ")
  end

  private

  def offline_line(row)
    return "Noch keine Statusmeldung" if row.last_seen_at.nil?
    minutes = (row.age / 60).round
    "Keine Statusmeldung seit #{minutes} min"
  end

  def schedule_part(row)
    if row.next_edge
      arrow = row.next_edge.action == :on ? "an" : "aus"
      "nächste Schaltung: #{row.next_edge.at.strftime('%H:%M')} → #{arrow}"
    else
      "kein Zeitplan"
    end
  end
end
