# frozen_string_literal: true

module TasksHelper
  # The form's "On whose list": everybody on the team, then — for those who
  # may see invitations — the people asked on who have not joined yet.
  def list_owner_options
    people = current_team.users.order(:first_name, :email).map { |user| [ user.name, user.id.to_s ] }
    invited = policy_scope(current_team.invitations).unaccepted.order(:email)
    people + invited.map { |invitation| [ "#{invitation.email} (invited)", "invitation_#{invitation.id}" ] }
  end

  def list_owner_label(task)
    return "#{task.invitation.email} (invited)" if task.invitation

    task.assignee&.name || "Nobody yet"
  end

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

  # Old-school text faces for inbox zero. One is picked when the page loads,
  # and checklist_controller.js swaps in another each time the list empties.
  INBOX_ZERO_FACES = [
    '\(^o^)/',
    '\o/',
    "ヽ(⌐■_■)ノ♪♬",
    "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧",
    "┏(-_-)┛┗(-_-)┓",
    "ᕕ( ᐛ )ᕗ",
    "(づ｡◕‿‿◕｡)づ",
    "♪┏(・o･)┛♪",
    "ʕ•ᴥ•ʔ",
    "٩(◕‿◕)۶",
    "ᕦ(ò_óˇ)ᕤ",
    "(~˘▾˘)~",
    "( ˘▽˘)っ♨",
    "(￣o￣) zzZZ",
    '¯\_(ツ)_/¯',
    "<(^_^)>",
    "☆*:.｡.o(≧▽≦)o.｡.:*☆",
    "8-D"
  ].freeze

  def inbox_zero_face = INBOX_ZERO_FACES.sample

  # The talk shortcut, in the words printed on this person's keyboard.
  # quick_add_controller.js listens for Cmd+Shift+V on a Mac and Ctrl+Shift+V
  # everywhere else.
  def voice_shortcut_label = request.user_agent.to_s.include?("Macintosh") ? "⌘⇧V" : "Ctrl+Shift+V"

  def today_label = Time.current.strftime("%A %-d %B")

  # A day on the done pile: "Today", "Yesterday", then the weekday and date.
  # The year only shows once it is not this one.
  def day_label(date)
    today = Time.zone.today
    return "Today" if date == today
    return "Yesterday" if date == today.yesterday

    date.strftime(date.year == today.year ? "%A %-d %B" : "%A %-d %B %Y")
  end

  # The done pile's day picker: every day with something finished, newest
  # first, each with its count. A picked day with nothing in it still gets a
  # place, so the picker never claims to show every day when it does not.
  def day_options(days, selected)
    days = days.merge(selected => 0) { |_, count| count } if selected
    options = days.sort_by { |day, _| day }.reverse.map { |day, count| [ "#{day_label(day)} · #{count}", day.iso8601 ] }

    options_for_select([ [ "Every day", "" ], *options ], selected&.iso8601)
  end

  # A day's bar on the month chart, as a screen reader hears it.
  def chart_day_label(date, count) = "#{date.strftime("%A %-d %B")}: #{pluralize(count, "task")} done"

  # The dashboard list a task still to do belongs in. Every stream that puts a
  # row back asks this, so a priority task never lands in the rest.
  def task_list_id(task) = task.priority? ? "priorities" : "tasks"

  # The tallies of what one person finished today — the one in the masthead,
  # the one over their jar — are marked with whose they are, so a stream about
  # a colleague's list never moves your own number.
  def done_count_selector(user) = %([data-done-count="#{user&.id}"])

  def greeting(user)
    hour = Time.current.hour
    part = if hour < 5 then "Burning the midnight oil"
    elsif hour < 12 then "Good morning"
    elsif hour < 17 then "Good afternoon"
    else "Good evening"
    end

    "#{part}, #{user.first_name.presence || "friend"}."
  end

  # What a list is called: "To do" when it is yours, the person's name when
  # it is a colleague's.
  def list_title(person) = person == Current.user ? "To do" : "#{person.first_name.presence || person.name}’s list"

  # The line beside the title: a greeting on your own list, the plain count
  # on a colleague's.
  def list_summary(person, pending, done)
    return "#{greeting(person)} #{plate_summary(pending, done)}" if person == Current.user

    "#{pluralize(pending, "thing")} to do, #{done} done today. Add one above and it is theirs."
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
  #
  # An app link opens the Claude or Codex conversation instead. It gets no
  # target: there is no page to open, and a new tab would be left blank.
  def open_link(task, label = nil, css: "btn-link", **options)
    return if task.link.nil?
    return link_to(label || "Open in #{task.app_name} ↗", task.link, class: css, **options) if task.app_link?

    link_to label || "Open ↗", task.link, class: css, target: "_blank", rel: "noopener noreferrer", **options
  end

  # The sources whose logo leads a task's title. Codex wears OpenAI's. The
  # files come from thesvg.org and are ours, so they are safe to inline, and
  # inline is what lets OpenAI's black mark take the text colour in dark mode.
  SOURCE_LOGOS = %w[claude codex slack].index_with { |source|
    Rails.root.join("app/assets/images/sources/#{source}.svg").read.strip.html_safe
  }.freeze

  # A task's title, led by its source's logo where it has one. The logo is
  # decoration: the source column already names it, so it says nothing to a
  # screen reader.
  def task_title(task)
    logo = SOURCE_LOGOS[task.source]
    return task.headline unless logo

    safe_join([ tag.span(logo, class: "source-logo"), task.headline ])
  end

  # Where the work came from, in plain words. Colour belongs to the project.
  # A task handed to an agent says who has it until the agent reports back.
  def source_badge(task)
    tag.span(task.with_agent? ? "With #{task.handed_to_name}" : task.source_label, class: "source")
  end

  # Starts a new Claude or Codex session on the task. A real form posted
  # without Turbo: see Tasks::HandoffsController for why.
  def hand_off_button(task, agent)
    button_to "Complete on #{Task::SOURCES.fetch(agent)} ↗", task_handoff_path(task),
      params: { agent: agent }, class: "btn btn--sm", form: { data: { turbo: false } }
  end

  def project_name(project) = project&.name || Project::OTHER

  # The project headline over a row's title: Other when there is none. Click
  # it to go back to where the project's work last happened; see
  # ProjectsHelper#project_link. The id is what the picker's stream replaces;
  # the project id is how grouped_controller.js knows where the row belongs.
  def project_badge(task)
    tag.span(project_tag(task.project), id: dom_id(task, :project), class: "checklist__project",
      data: { project_id: task.project_id.to_s })
  end

  # How old a task is, short enough for a column: "now", "12m", "3h", "4d".
  def short_age(time)
    seconds = Time.current - time
    return "now" if seconds < 1.minute
    return "#{(seconds / 1.minute).floor}m" if seconds < 1.hour
    return "#{(seconds / 1.hour).floor}h" if seconds < 1.day

    "#{(seconds / 1.day).floor}d"
  end

  # The age column: how long since anyone — a person or an agent — last
  # touched the task. A task left alone for a while says so, "quiet" rather
  # than "overdue": nothing here has a deadline, it has just been forgotten,
  # which is the problem the app exists to solve.
  def task_age(task)
    heard = task.last_activity_at
    tag.time(short_age(heard), datetime: heard.iso8601,
      class: [ "checklist__age", "numeric", ("is-quiet" if task.quiet?) ],
      title: task.quiet? ? "Quiet for #{time_ago_in_words(heard)}" : "Last heard #{time_ago_in_words(heard)} ago")
  end
end
