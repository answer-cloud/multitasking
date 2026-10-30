# frozen_string_literal: true

# The team's projects. Most arrive on their own, made by the first task an
# agent pushes in from a new repository; this is where they get renamed, given
# a folder, or cleared away.
class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update destroy]

  def index
    @projects = policy_scope(scoped_projects.alphabetical)
    @open_counts = current_team.tasks.pending.group(:project_id).count
  end

  def show
    authorize @project
    @tasks = @project.tasks.pending.in_order
    @done = @project.tasks.done.recently_done
  end

  def new
    @project = scoped_projects.new
    authorize @project
  end

  def create
    @project = scoped_projects.new(project_params)
    @project.created_by = Current.user
    authorize @project

    if @project.save
      redirect_to @project, notice: "Project created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @project
  end

  def update
    authorize @project

    if @project.update(project_params)
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @project
    @project.destroy!

    redirect_to projects_path, notice: "Project deleted. Its tasks are still on the list.", status: :see_other
  end

  private

  # The one line that matters.
  def scoped_projects = current_team.projects

  def set_project
    @project = scoped_projects.find(params[:id])
  end

  def project_params
    params.expect(project: %i[name alias_list directory color])
  end
end
