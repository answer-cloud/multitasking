# frozen_string_literal: true

# One thing to get done, wherever it came from, on one person's list.
#
# A task has an assignee: whoever's list it is on. You add to your own list by
# default, and to a colleague's by assigning it — from their list, from the
# edit form, or by asking Claude. A task with nobody on it waits on the team
# page.
#
# A task is typed or spoken into the app, or pushed in by another tool — a
# Claude Code or Codex hook, a 📌 in Slack, later Chrome and email. Pushed
# tasks carry an `external_id`, so a second ping about the same session moves
# the task back to the top instead of adding a duplicate.
# == Schema Information
#
# Table name: tasks
#
#  id               :bigint           not null, primary key
#  completed_at     :datetime
#  handed_at        :datetime
#  handed_to        :string
#  last_activity_at :datetime         not null
#  low_priority     :boolean          default(FALSE), not null
#  notes            :text
#  position         :integer          default(0), not null
#  priority         :boolean          default(FALSE), not null
#  source           :string           default("typed"), not null
#  title            :string           not null
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  assignee_id      :bigint
#  created_by_id    :bigint
#  external_id      :string
#  invitation_id    :bigint
#  project_id       :bigint
#  team_id          :bigint           not null
#
# Indexes
#
#  index_tasks_on_created_by_id                             (created_by_id)
#  index_tasks_on_invitation_id                             (invitation_id)
#  index_tasks_on_project_id                                (project_id)
#  index_tasks_on_team_id                                   (team_id)
#  index_tasks_on_team_id_and_assignee_id_and_completed_at  (team_id,assignee_id,completed_at)
#  index_tasks_on_team_id_and_completed_at                  (team_id,completed_at)
#  index_tasks_on_team_id_and_source_and_external_id        (team_id,source,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (assignee_id => users.id) ON DELETE => nullify
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (invitation_id => team_invitations.id) ON DELETE => nullify
#  fk_rails_...  (project_id => projects.id) ON DELETE => nullify
#  fk_rails_...  (team_id => teams.id)
#
class Task < ApplicationRecord
  include TenantScoped

  SOURCES = {
    "typed"  => "Typed",
    "voice"  => "Spoken",
    "tab"    => "Tab",
    "claude" => "Claude",
    "codex"  => "Codex",
    "chrome" => "Chrome",
    "slack"  => "Slack",
    "email"  => "Email",
    "social" => "Social"
  }.freeze

  # The sources a signed-in person can pick from inside the app: the quick-add
  # box, the microphone, and the save-this-tab bookmarklet. Everything else
  # arrives through the inbox with a token.
  IN_APP_SOURCES = %w[typed voice tab].freeze

  # The deep links that open a conversation back up in the Claude or Codex
  # desktop app. Exactly these two shapes and no other custom scheme: a
  # browser hands an unknown scheme to whichever app claims it.
  APP_LINK = %r{\A(?:claude://code/continue\?session=local_[\w-]+|codex://threads/[\w-]+)\z}

  # The agents a task can be handed to from its row. See #agent_link.
  AGENTS = %w[claude codex].freeze

  # What script/agent-hook puts in front of a finished session's title. The
  # list shows the agent's logo there instead; see TasksHelper#task_title.
  # "Claude needs you:" stays, because it says something the logo cannot.
  REVIEW_PREFIX = /\AReview (?:Claude|Codex): /

  # Long enough for a whole first prompt from an agent session, which is
  # what its task is called. The list shows titles in full, never cut.
  TITLE_LIMIT = 2_000

  # A task nobody has touched for this long gets a nudge in the list.
  QUIET_AFTER = 2.days

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :project, optional: true
  # Set while the task waits for somebody invited to the team: it has no
  # assignee until they accept, and then it is theirs.
  belongs_to :invitation, class_name: "TeamInvitation", optional: true

  validates :title, presence: true, length: { maximum: TITLE_LIMIT }
  validates :notes, length: { maximum: 10_000 }
  validates :source, inclusion: { in: SOURCES.keys }
  validates :url, length: { maximum: 2_000 }
  validates :handed_to, inclusion: { in: AGENTS }, allow_nil: true
  validate :url_is_a_web_link
  validate :project_is_on_this_team
  validate :assignee_is_on_this_team, if: :assignee_id_changed?
  validate :invitation_is_open_on_this_team, if: :invitation_id_changed?
  validate :not_both_priorities

  # On somebody's list, it waits for nobody.
  before_validation { self.invitation = nil if assignee_id }

  before_validation :touch_activity, on: :create
  before_create :put_on_top
  # Handed to somebody else, it lands on top of their list like anything new.
  before_update :put_on_top, if: :assignee_id_changed?

  # One person's list. Nil is nobody's: the tasks waiting on the team page.
  scope :assigned_to, ->(user) { where(assignee: user) }
  # What exists for this person at all: everything for an admin, and for
  # anybody else everything outside the projects kept to admins. The policy
  # scopes call this; so do broadcasts, which have no request to ask.
  scope :visible_to, ->(membership) {
    next none if membership.nil?
    next all if membership.admin_or_above?

    outside(membership.team.projects.admin_only.ids)
  }
  scope :pending, -> { where(completed_at: nil) }
  scope :done, -> { where.not(completed_at: nil) }
  scope :prioritized, -> { where(priority: true) }
  # The middle list: neither a priority nor put off as low priority.
  scope :unprioritized, -> { where(priority: false, low_priority: false) }
  scope :low_prioritized, -> { where(low_priority: true) }
  scope :done_today, -> { where(completed_at: Time.current.beginning_of_day..) }
  scope :fresh_first, -> { order(last_activity_at: :desc) }
  # The order you dragged them into. Ties — every task from before dragging —
  # fall back to freshest first, which is the order they were already in.
  scope :in_order, -> { order(:position, last_activity_at: :desc) }
  scope :recently_done, -> { order(completed_at: :desc) }
  scope :done_on, ->(day) {
    next all if day.blank?

    where(completed_at: day.in_time_zone.all_day)
  }
  # Everything not filed under these projects. Unfiled tasks count as outside:
  # NOT IN on its own would drop them too, because NULL is never NOT IN.
  scope :outside, ->(project_ids) {
    next all if project_ids.blank?

    where("tasks.project_id IS NULL OR tasks.project_id NOT IN (?)", project_ids)
  }
  scope :search, ->(term) {
    next all if term.blank?

    pattern = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("title ILIKE :q OR notes ILIKE :q", q: pattern)
  }

  # How many were finished on each day, newest day first, as { Date => count }.
  # The day is cut in the app's time zone, not the database's, so it agrees
  # with done_on and with what "today" means everywhere else.
  def self.days_done
    day = sanitize_sql_array([ "DATE(completed_at AT TIME ZONE 'UTC' AT TIME ZONE ?)", Time.zone.tzinfo.identifier ])
    done.unscope(:order).group(Arel.sql(day)).order(Arel.sql("#{day} DESC")).count
  end

  def done? = completed_at.present?

  def quiet? = !done? && last_activity_at < QUIET_AFTER.ago

  def source_label = SOURCES.fetch(source, source.humanize)

  # The title as the list shows it: without the hook's "Review Claude: ".
  def headline = title.sub(REVIEW_PREFIX, "")

  # The url, but only if it is a web link or an app link — what a view may put
  # in an href. Validation already refuses anything else; this is the second
  # lock, for a row that predates the validation or was written around it.
  def link = (url if web_link?(url) || app_link?)

  def app_link? = url.to_s.match?(APP_LINK)

  # "Claude" or "Codex", for an app link.
  def app_name = (SOURCES[url[/\A\w+/]] if app_link?)

  # "Claude" or "Codex", once the task has been handed to one.
  def handed_to_name = (SOURCES[handed_to] if handed_to)

  # Handed over, and the agent's session has not reported back yet. Once it
  # does, the inbox takes the task over and it is the agent's own.
  def with_agent? = handed_to.present? && external_id.nil?

  # Working on a task includes giving it to somebody else to do.
  def hand_to!(agent) = update!(handed_to: agent, handed_at: Time.current, last_activity_at: Time.current)

  # What the agent is asked to do: the task, and its notes if it has any.
  def agent_prompt = [ title, notes.presence ].compact.join("\n\n")

  # Starts a new session in the agent's desktop app with the task already
  # typed in, in the project's folder when it has one. Nothing is sent until
  # you press return there — the app only fills the box.
  #
  # These are the apps' own "new session" links, and they differ: Claude reads
  # `q` and `folder`, Codex `prompt` and `path`. Change one only against the
  # app that reads it.
  def agent_link(agent)
    folder = project&.directory

    case agent
    when "claude" then "claude://code/new?#{{ q: agent_prompt, folder: folder }.compact.to_query}"
    when "codex" then "codex://threads/new?#{{ prompt: agent_prompt, path: folder }.compact.to_query}"
    end
  end

  def complete! = update!(completed_at: Time.current)

  def reopen!
    put_on_top
    update!(completed_at: nil, last_activity_at: Time.current)
  end

  # Pinned in the priority list above everything else, put off into the low
  # priority list under the rest, or brought back into the rest. Either way it
  # lands on top of the list it joins. Not activity, like moving it: ranking a
  # task is not working on it.
  def prioritize!     = place_in_list!(priority: true, low_priority: false)
  def low_prioritize! = place_in_list!(priority: false, low_priority: true)
  def deprioritize!   = place_in_list!(priority: false, low_priority: false)

  # Above everything else still to do in its own list — priority, the rest, or
  # low priority.
  # New tasks, reopened ones, and ones an agent pings about again all land
  # here — the same place the dashboard's stream prepends them, so a reload
  # agrees with what was on screen.
  def put_on_top
    self.position = siblings.minimum(:position).to_i - 1
  end

  # The stream an open copy of its assignee's list listens to. One per
  # person, so a task never shows up on a list it is not on.
  def stream = [ team, assignee, :tasks ]

  # Whose list it is on, as the form's picker says it: a person's id, or an
  # invitation's. See TasksController#owner_attributes.
  def owner = invitation_id ? "invitation_#{invitation_id}" : assignee_id&.to_s

  # The name to show for that: the person's, or the address they were invited at.
  def owner_name = assignee&.name || invitation&.email

  # The projects its row's picker offers: the ones its assignee can see. For
  # the broadcasts, which render the row with nobody signed in.
  def pickable_projects = team.projects.visible_to(assignee&.membership_for(team)).alphabetical.to_a

  # Moves the task to the top of any open copy of its assignee's list, and out
  # of the jar if it had been ticked off. A priority task stays in the
  # priority list. For tasks that arrive from outside — the inbox, Slack —
  # where no request is there to answer with a stream of its own. Nobody's
  # task is on no list, so there is nothing to tell.
  def broadcast_arrival
    return if assignee.nil?

    Turbo::StreamsChannel.broadcast_remove_to(*stream, target: self)
    Turbo::StreamsChannel.broadcast_remove_to(*stream, target: ActionView::RecordIdentifier.dom_id(self, :done))
    Turbo::StreamsChannel.broadcast_prepend_to(*stream, target: ApplicationController.helpers.task_list_id(self), partial: "tasks/task",
                                                        locals: { task: self, projects: pickable_projects })
    Turbo::StreamsChannel.broadcast_update_to(*stream, targets: ApplicationController.helpers.done_count_selector(assignee),
                                                       html: team.tasks.assigned_to(assignee).done_today.count.to_s)
  end

  # Drops the task into its list of things still to do at `index`, counting
  # from 0 at the top, and renumbers the list to match. Absolute, so a retried
  # request lands in the same place.
  def move_to(index)
    order = siblings.in_order.ids
    order.insert(index.to_i.clamp(0, order.size), id)

    transaction do
      order.each_with_index { |task_id, position| team.tasks.where(id: task_id).update_all(position: position) }
    end
  end

  private

  # The other tasks still to do in the same list as this one: the same
  # person's, and the priority list, the rest and the low priority list are
  # numbered separately, so dragging in one never shuffles another.
  def siblings = team.tasks.pending.assigned_to(assignee).where(priority: priority, low_priority: low_priority).where.not(id: id)

  def place_in_list!(priority:, low_priority:)
    self.priority = priority
    self.low_priority = low_priority
    put_on_top
    save!
  end

  # A task is in one list. Both flags at once would number it with neither.
  def not_both_priorities
    return unless priority? && low_priority?

    errors.add(:low_priority, "cannot be set on a priority task")
  end

  def web_link?(value)
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def url_is_a_web_link
    return if url.blank? || web_link?(url) || app_link?

    errors.add(:url, "must be a web link starting with http:// or https://")
  end

  # Controllers look a chosen project up through the team, so this should never
  # fire. It is here because a task filed under another team's project would
  # show that team's project name to this one.
  def project_is_on_this_team
    return if project.nil? || project.team_id == team_id

    errors.add(:project, "must belong to this team")
  end

  # Controllers offer only the team's own people, so this should never fire.
  # It is here because an id in a form is only a claim, and a task on a
  # stranger's list would show them this team's work.
  def invitation_is_open_on_this_team
    return if invitation.nil? || (invitation.team_id == team_id && !invitation.accepted?)

    errors.add(:invitation, "must be an open invitation to this team")
  end

  def assignee_is_on_this_team
    return if assignee.nil? || assignee.member_of?(team)

    errors.add(:assignee, "must be on this team")
  end

  def touch_activity
    self.last_activity_at ||= Time.current
  end
end
