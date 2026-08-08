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

  # The text of one schedule row, for both kinds: "Mo–Fr · 10:00–20:00" for a
  # Zeitfenster, "täglich · 22:00" for an Einzelschaltung — the direction of a
  # single is markup, not text, and stays in the component.
  #
  # Both kinds answer +days+ and +rules+, so neither the weekdays nor the times
  # need a branch here. A window's rules are its on and its off rule in that
  # order, and its days are the on rule's — which is exactly the day shift of a
  # window past midnight undone: "22:00 an Mo–Fr, 06:00 aus Di–Sa" reads back
  # as "Mo–Fr · 22:00–06:00".
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
