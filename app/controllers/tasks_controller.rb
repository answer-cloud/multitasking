# frozen_string_literal: true

# The task list. The dashboard shows what is still to do; this index is the
# done pile, searchable and paged, so finished work is never truly gone.
class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy]

  def index
    @tasks = policy_scope(scoped_tasks.done.search(params[:q]).recently_done)
    @page = paginate(@tasks)
  end

  def show
    authorize @task
  end

  # Quick add, from the box at the top of the dashboard. Typed or spoken, it
  # lands here; the `source` says which.
  def create
    @task = scoped_tasks.new(task_params)
    @task.created_by = Current.user
    @task.source = "typed" unless @task.source.in?(%w[typed voice])
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
      redirect_to @task, notice: "Task updated."
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

  def task_params
    params.expect(task: %i[title notes url source])
  end
end
