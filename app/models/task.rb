# frozen_string_literal: true

# One thing to get done, wherever it came from.
#
# A task is typed or spoken into the app, or pushed in by another tool — a
# Claude Code or Codex hook, later Chrome, Slack and email. Pushed tasks carry
# an `external_id`, so a second ping about the same session moves the task back
# to the top instead of adding a duplicate.
# == Schema Information
#
# Table name: tasks
#
#  id               :bigint           not null, primary key
#  completed_at     :datetime
#  handed_at        :datetime
#  handed_to        :string
#  last_activity_at :datetime         not null
#  notes            :text
#  position         :integer          default(0), not null
#  priority         :boolean          default(FALSE), not null
#  source           :string           default("typed"), not null
#  title            :string           not null
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  created_by_id    :bigint
#  external_id      :string
#  project_id       :bigint
#  team_id          :bigint           not null
#
# Indexes
#
#  index_tasks_on_created_by_id                       (created_by_id)
#  index_tasks_on_project_id                          (project_id)
#  index_tasks_on_team_id                             (team_id)
#  index_tasks_on_team_id_and_completed_at            (team_id,completed_at)
#  index_tasks_on_team_id_and_source_and_external_id  (team_id,source,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
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

  # Long enough for a whole first prompt from an agent session, which is
  # what its task is called. The list shows titles in full, never cut.
  TITLE_LIMIT = 2_000

  # A task nobody has touched for this long gets a nudge in the list.
  QUIET_AFTER = 2.days

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :project, optional: true

  validates :title, presence: true, length: { maximum: TITLE_LIMIT }
  validates :notes, length: { maximum: 10_000 }
  validates :source, inclusion: { in: SOURCES.keys }
  validates :url, length: { maximum: 2_000 }
  validates :handed_to, inclusion: { in: AGENTS }, allow_nil: true
  validate :url_is_a_web_link
  validate :project_is_on_this_team

  before_validation :touch_activity, on: :create
  before_create :put_on_top

  scope :pending, -> { where(completed_at: nil) }
  scope :done, -> { where.not(completed_at: nil) }
  scope :prioritized, -> { where(priority: true) }
  scope :unprioritized, -> { where(priority: false) }
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

  # Pinned in the priority list above everything else, or let back down into
  # the rest. Either way it lands on top of the list it joins. Not activity,
  # like moving it: ranking a task is not working on it.
  def prioritize! = place_in_list!(priority: true)
  def deprioritize! = place_in_list!(priority: false)

  # Above everything else still to do in its own list — priority or the rest.
  # New tasks, reopened ones, and ones an agent pings about again all land
  # here — the same place the dashboard's stream prepends them, so a reload
  # agrees with what was on screen.
  def put_on_top
    self.position = siblings.minimum(:position).to_i - 1
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

  # The other tasks still to do in the same list as this one. The priority
  # list and the rest are numbered separately, so dragging in one never
  # shuffles the other.
  def siblings = team.tasks.pending.where(priority: priority).where.not(id: id)

  def place_in_list!(priority:)
    self.priority = priority
    put_on_top
    save!
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

  def touch_activity
    self.last_activity_at ||= Time.current
  end
end
