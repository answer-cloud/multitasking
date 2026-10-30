# frozen_string_literal: true

# The front door: what is left to do, and what has already gone in the jar
# today.
class DashboardController < ApplicationController
  # The two ways to cut the list: one list in the order you keep it, or one
  # per project. The first is the default.
  VIEWS = %w[tasks projects].freeze

  def show
    authorize current_team, :show?, policy_class: TeamPolicy

    # Everything here starts from the team, not from the model class.
    @priorities = policy_scope(pending.prioritized)
    @tasks = policy_scope(pending.unprioritized)
    @projects = current_team.projects.alphabetical.to_a
    @done_today = policy_scope(current_team.tasks.done_today.recently_done.includes(:project))
    @new_task = current_team.tasks.new
    @view = view
    @groups = by_project(@tasks) if @view == "projects"
  end

  private

  # Everything still to do, in list order. The priority list and the rest are
  # both cut from it.
  def pending = current_team.tasks.pending.in_order.includes(:created_by, :project)

  # Remembered, so the dashboard opens the way you left it.
  def view
    cookies.permanent[:dashboard_view] = params[:view] if VIEWS.include?(params[:view])
    VIEWS.include?(cookies[:dashboard_view]) ? cookies[:dashboard_view] : VIEWS.first
  end

  # Projects A to Z, Other last. Each keeps its tasks in list order.
  def by_project(tasks)
    tasks.group_by(&:project).sort_by { |project, _| project ? [ 0, project.name.downcase ] : [ 1, "" ] }
  end
end
