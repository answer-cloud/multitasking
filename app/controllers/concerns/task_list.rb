# frozen_string_literal: true

# One person's list: what they have still to do, and what went in their jar
# today. The dashboard shows your own; PeopleController shows a colleague's.
# Both render dashboard/show.
module TaskList
  extend ActiveSupport::Concern

  # The two ways to cut the list: one list in the order you keep it, or one
  # per project. The first is the default.
  VIEWS = %w[tasks projects].freeze

  private

  # `hidden_project_ids` are the projects to leave out: your own hidden ones
  # on your own list, none on anybody else's — hiding is about your view of
  # your list, not theirs.
  def load_task_list(person, hidden_project_ids: [])
    @person = person
    pending = list_of(person).pending.outside(hidden_project_ids).in_order.includes(:created_by, :project)

    @priorities = pending.prioritized
    @tasks = pending.unprioritized
    @projects = visible_projects.alphabetical.to_a
    @new_task = current_team.tasks.new(assignee: person)
    @view = list_view
    @groups = by_project(@tasks) if @view == "projects"
    load_done_today
  end

  # What went in the person's jar today, and Claude's note on the team's day
  # — written at 9pm, so nil for most of it.
  def load_done_today
    @done_today = list_of(@person).done_today.recently_done.includes(:project)
    @summary = policy_scope(current_team.daily_summaries).find_by(day: Date.current)
  end

  # Everything starts from the team, then the policy scope, then the person.
  def list_of(person) = policy_scope(current_team.tasks).assigned_to(person)

  # Remembered, so a list opens the way you left the last one.
  def list_view
    cookies.permanent[:dashboard_view] = params[:view] if VIEWS.include?(params[:view])
    VIEWS.include?(cookies[:dashboard_view]) ? cookies[:dashboard_view] : VIEWS.first
  end

  # Projects A to Z, Other last. Each keeps its tasks in list order.
  def by_project(tasks)
    tasks.group_by(&:project).sort_by { |project, _| project ? [ 0, project.name.downcase ] : [ 1, "" ] }
  end
end
