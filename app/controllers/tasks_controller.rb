# frozen_string_literal: true

# The task list. The dashboard shows what is still to do; this index is the
# done pile, searchable, paged and grouped by day, so finished work is never
# truly gone.
class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy]

  def index
    done = policy_scope(scoped_tasks.done.search(params[:q]))
    @days = done.days_done
    @day = day
    @page = paginate(done.done_on(@day).recently_done)
  end

  def show
    authorize @task
  end

  # Where the save-this-tab bookmarklet lands, with the page's title and
  # address in the query string. It only fills the form in: a GET must never
  # add a task, or any page could add one by linking here.
  def new
    @task = scoped_tasks.new(
      title: (params[:title].presence || params[:url]).to_s.squish.first(Task::TITLE_LIMIT),
      url: params[:url].to_s.first(2_000).presence,
      source: "tab"
    )
    authorize @task
  end

  # Quick add, from the box at the top of the dashboard. Typed or spoken, it
  # lands here; the `source` says which.
  def create
    @task = build_quick_add_task
    authorize @task

    if @task.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to dashboard_path, notice: "Added." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :create_failed, status: :unprocessable_content }
        format.html { redirect_to dashboard_path, alert: @task.errors.full_messages.to_sentence }
      end
    end
  end

  def edit
    authorize @task
  end

  def update
    authorize @task

    if @task.update(task_params.merge(last_activity_at: Time.current))
      redirect_to dashboard_path, notice: "Task updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @task
    @task.destroy!

    redirect_to dashboard_path, notice: "Task deleted.", status: :see_other
  end

  private

  # The one line that matters.
  def scoped_tasks = current_team.tasks

  def set_task
    @task = scoped_tasks.find(params[:id])
  end

  # The day picked on the done pile, or nil for every day. A day that is not a
  # date is treated as no day rather than an error.
  def day
    Date.iso8601(params[:day].to_s)
  rescue Date::Error
    nil
  end

  def build_quick_add_task
    task = scoped_tasks.new(task_params)
    task.created_by = Current.user
    task.source = "typed" unless task.source.in?(Task::IN_APP_SOURCES)
    file_under_leading_name(task)
    task
  end

  # Quick add's shorthand: "Acme send the invoice", typed or said, files the
  # task under Acme and drops the name from the title. Only for a task nobody
  # has filed already, and never a saved tab — its title is the page's, not
  # something you wrote.
  def file_under_leading_name(task)
    return if task.project || task.source == "tab"

    project, rest = current_team.projects.leading(task.title)
    return if project.nil?

    task.project = project
    task.title = rest
  end

  def task_params
    params.expect(task: %i[title notes url source project_id])
  end
end
