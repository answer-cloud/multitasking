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
#  last_activity_at :datetime         not null
#  notes            :text
#  source           :string           default("typed"), not null
#  title            :string           not null
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  created_by_id    :bigint
#  external_id      :string
#  team_id          :bigint           not null
#
# Indexes
#
#  index_tasks_on_created_by_id                       (created_by_id)
#  index_tasks_on_team_id                             (team_id)
#  index_tasks_on_team_id_and_completed_at            (team_id,completed_at)
#  index_tasks_on_team_id_and_source_and_external_id  (team_id,source,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (team_id => teams.id)
#
class Task < ApplicationRecord
  include TenantScoped

  SOURCES = {
    "typed"  => "Typed",
    "voice"  => "Spoken",
    "claude" => "Claude",
    "codex"  => "Codex",
    "chrome" => "Chrome",
    "slack"  => "Slack",
    "email"  => "Email",
    "social" => "Social"
  }.freeze

  # A task nobody has touched for this long gets a nudge in the list.
  QUIET_AFTER = 2.days

  belongs_to :created_by, class_name: "User", optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :notes, length: { maximum: 10_000 }
  validates :source, inclusion: { in: SOURCES.keys }
  validates :url, length: { maximum: 2_000 }
  validate :url_is_a_web_link

  before_validation :touch_activity, on: :create

  scope :pending, -> { where(completed_at: nil) }
  scope :done, -> { where.not(completed_at: nil) }
  scope :done_today, -> { where(completed_at: Time.current.beginning_of_day..) }
  scope :fresh_first, -> { order(last_activity_at: :desc) }
  scope :recently_done, -> { order(completed_at: :desc) }
  scope :search, ->(term) {
    next all if term.blank?

    pattern = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("title ILIKE :q OR notes ILIKE :q", q: pattern)
  }

  def done? = completed_at.present?

  def quiet? = !done? && last_activity_at < QUIET_AFTER.ago

  def source_label = SOURCES.fetch(source, source.humanize)

  # The url, but only if it is a web link — what a view may put in an href.
  # Validation already refuses anything else; this is the second lock, for a
  # row that predates the validation or was written around it.
  def link = (url if web_link?(url))

  def complete! = update!(completed_at: Time.current)

  def reopen! = update!(completed_at: nil, last_activity_at: Time.current)

  private

  def web_link?(value)
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def url_is_a_web_link
    return if url.blank? || web_link?(url)

    errors.add(:url, "must be a web link starting with http:// or https://")
  end

  def touch_activity
    self.last_activity_at ||= Time.current
  end
end
