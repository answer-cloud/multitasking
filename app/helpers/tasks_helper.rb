# frozen_string_literal: true

module TasksHelper
  # Rotating examples for the quick-add box. A blank box asks "what?"; an
  # example answers it.
  QUICK_ADD_EXAMPLES = [
    "Reply to Sam about the deck",
    "Check on that Claude run in the api repo",
    "Finish the Chrome tab I left open",
    "Book the dentist, for real this time",
    "Read the thread in #design",
    "Ship the thing"
  ].freeze

  def quick_add_placeholder = "e.g. #{QUICK_ADD_EXAMPLES.sample}"

  def greeting(user)
    hour = Time.current.hour
    part = if hour < 5 then "Burning the midnight oil"
    elsif hour < 12 then "Good morning"
    elsif hour < 17 then "Good afternoon"
    else "Good evening"
    end

    "#{part}, #{user.first_name.presence || "friend"}."
  end

  # The line under the greeting. It reads the room.
  def plate_summary(pending, done)
    return "Nothing on your plate. Suspicious. Add something?" if pending.zero? && done.zero?
    return "Everything’s in the jar. Go stretch your legs." if pending.zero?
    return "#{pluralize(pending, "thing")} on your plate. Let’s knock one out." if done.zero?

    "#{pluralize(pending, "thing")} to go, #{done} already in the jar."
  end

  # A link out to where the task came from — the tab, thread or PR. Opens in a
  # new tab so the list stays put. Task#link is nil for anything that is not a
  # web link, so this renders nothing rather than a dangerous href.
  def open_link(task, label = "Open ↗", css: "btn-link")
    return if task.link.nil?

    link_to label, task.link, class: css, target: "_blank", rel: "noopener noreferrer"
  end

  def source_badge(task)
    tag.span(task.source_label, class: "badge badge--quiet source source--#{task.source}")
  end

  # "Quiet" rather than "overdue": nothing here has a deadline, it has just
  # been forgotten, which is the problem the app exists to solve.
  def quiet_note(task)
    return unless task.quiet?

    tag.span("quiet for #{time_ago_in_words(task.last_activity_at)}", class: "checklist__quiet")
  end
end
