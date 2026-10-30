# frozen_string_literal: true

# What a task is part of — a client, a product, a repository.
#
# A project can carry the folder an agent works in. A task pushed in from a
# Claude Code or Codex session in that folder, or anywhere below it, files
# itself under the project; the first task from a repository nobody has filed
# yet makes the project. See Inbox::TasksController.
# == Schema Information
#
# Table name: projects
#
#  id            :bigint           not null, primary key
#  aliases       :string           default([]), not null, is an Array
#  color         :string
#  directory     :string
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#  team_id       :bigint           not null
#
# Indexes
#
#  index_projects_on_created_by_id          (created_by_id)
#  index_projects_on_team_id                (team_id)
#  index_projects_on_team_id_and_directory  (team_id,directory) UNIQUE WHERE (directory IS NOT NULL)
#  index_projects_on_team_id_and_name       (team_id,name)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (team_id => teams.id)
#
class Project < ApplicationRecord
  include TenantScoped

  # Absolute, because the hook sends absolute paths: "~/code/app" would never
  # match "/Users/you/code/app". A Windows drive counts too. One line only.
  ABSOLUTE_PATH = %r{\A(?:/|[A-Za-z]:[\\/]).*\z}

  # What a task filed under no project is called, wherever one is shown.
  OTHER = "Other"

  # The palette in abstracts/_variables.scss. A project wears one, so a glance
  # down the list says what each task belongs to. Ordered so neighbours differ:
  # projects made one after another, coloured by id, do not look alike.
  COLORS = %w[sun sky pink leaf lilac tangerine teal coral cobalt lime orchid sand].freeze

  belongs_to :created_by, class_name: "User", optional: true
  has_many :tasks, dependent: :nullify

  validates :name, presence: true, length: { maximum: 120 }
  validates :directory, length: { maximum: 1_000 },
                        uniqueness: { scope: :team_id, allow_nil: true },
                        format: { with: ABSOLUTE_PATH, allow_nil: true, message: "must be a full path, starting with /" }
  # It ends up in a class name, so only the palette's own words get through.
  validates :color, inclusion: { in: COLORS }
  validates :aliases, length: { maximum: 20, message: "can be at most 20 names" }
  validate :aliases_are_short

  normalizes :name, with: ->(name) { name.squish }
  normalizes :aliases, with: ->(aliases) { aliases.map(&:squish).compact_blank.uniq(&:downcase) }
  normalizes :directory, with: ->(directory) { normalize_directory(directory) }

  scope :alphabetical, -> { order(Arel.sql("lower(projects.name)")) }

  # A project nobody has picked a colour for — every one an agent makes, and
  # every one from before colours — gets one from its id. Stored as nil, so
  # do not query on the column: read it through here.
  def color = super || COLORS[id.to_i % COLORS.size]

  # The task most recently heard from that has somewhere to go back to — where
  # work on the project last happened. Ones with no link, like a spoken task,
  # are skipped for the next one down. Remembered, so a list with many rows
  # from one project asks once.
  def latest_linked_task
    return @latest_linked_task if defined?(@latest_linked_task)

    @latest_linked_task = tasks.where.not(url: [ nil, "" ]).fresh_first.detect(&:link)
  end

  # The other names a project answers to, as the form shows them: "Slater,
  # Slater Sweet". Mostly for voice, which hears what it likes.
  def alias_list = aliases.join(", ")

  def alias_list=(list)
    self.aliases = list.to_s.split(",")
  end

  # The project a title starts with — by its name or any of its aliases — and
  # the rest of the title. Case is ignored, hyphens and underscores read as
  # spaces, and a colon or comma after the name is dropped — so "slater-suite
  # fix it", "Slater Suite: fix it" and the spoken "slater suite fix it" all
  # find Slater Suite. The longest name wins, so "Slater Suite" beats
  # "Slater". Nil when the title starts with no project or is nothing but one.
  # Call it through a team's projects.
  def self.leading(title)
    words = title.to_s.split
    projects = {}
    all.each do |project|
      [ project.name, *project.aliases ].each { |name| projects[comparable(name)] ||= project }
    end

    (words.size - 1).downto(1) do |count|
      project = projects[comparable(words.first(count).join(" "))]
      return [ project, words.drop(count).join(" ") ] if project
    end
    nil
  end

  def self.comparable(name) = name.downcase.tr("-_", "  ").squish.sub(/[:,]\z/, "")
  private_class_method :comparable

  # "/code/app/" and "/code/app" are the same folder; a blank field is no folder.
  def self.normalize_directory(directory)
    directory = directory.to_s.strip
    directory = directory.chomp("/") while directory.length > 1 && directory.end_with?("/")
    directory.presence
  end

  # The project for an agent working in `path`: the one whose directory is that
  # folder or the nearest folder above it. Call it through a team's projects.
  def self.for_directory(path)
    path = normalize_directory(path)
    return if path.nil?

    where("directory = :path OR starts_with(:path, directory || '/')", path: path)
      .order(Arel.sql("length(directory) DESC"))
      .first
  end

  # Files an agent's folder under a project, making one the first time a task
  # comes from there. A project somebody made by hand with the folder's name
  # and no directory yet is adopted rather than duplicated.
  #
  # Nil when there is nothing sensible to file it under. A task must never fail
  # to arrive because its project could not be made.
  def self.claim_directory(path)
    path = normalize_directory(path)
    return if path.nil?

    for_directory(path) || adopt_directory(path) || make_for_directory(path)
  end

  def self.adopt_directory(path)
    project = where(directory: nil).find_by("lower(name) = ?", File.basename(path).downcase)
    project if project&.update(directory: path)
  end
  private_class_method :adopt_directory

  # create_or_find_by, so two pings from a new repository at the same moment
  # land on one project: the second insert hits the unique index and finds the
  # first.
  def self.make_for_directory(path)
    project = create_or_find_by(directory: path) { |new_project| new_project.name = File.basename(path).first(120) }
    project if project.persisted?
  end
  private_class_method :make_for_directory

  private

  def aliases_are_short
    errors.add(:aliases, "can each be at most 120 characters") if aliases.any? { |name| name.length > 120 }
  end
end
