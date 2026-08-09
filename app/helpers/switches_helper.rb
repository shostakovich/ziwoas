module SwitchesHelper
  DAY_ABBR = { 1 => "Mo", 2 => "Di", 3 => "Mi", 4 => "Do", 5 => "Fr", 6 => "Sa", 7 => "So" }.freeze
  SOURCE_LABEL = { "manual" => "manuell", "schedule" => "Zeitplan" }.freeze

  def weekday_label(days)
    sorted = days.sort
    return "täglich" if sorted == SwitchRule::ISO_DAYS
    sorted.slice_when { |a, b| b != a + 1 }
          .map { |group| group.size >= 2 ? "#{DAY_ABBR[group.first]}–#{DAY_ABBR[group.last]}" : DAY_ABBR[group.first] }
          .join(", ")
  end

  # "Mo–Fr · 10:00–20:00" for a Zeitfenster, "täglich · 22:00" for an
  # Einzelschaltung. Both kinds answer +days+ and +rules+, so no branch is
  # needed — and taking a window's days from its on rule reads the shift past
  # midnight back out: "22:00 an Mo–Fr, 06:00 aus Di–Sa" becomes "Mo–Fr ·
  # 22:00–06:00".
  def entry_label(entry)
    "#{weekday_label(entry.days)} · #{entry.rules.map(&:at_minute_time).join('–')}"
  end

  def switch_status_line(row)
    return offline_line(row) if row.offline?

    state_word = row.on? ? "an" : "aus"
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
    return "noch keine Statusmeldung" if row.last_seen_at.nil?
    minutes = ((row.now - row.last_seen_at) / 60).round
    "keine Statusmeldung seit #{minutes} min"
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
