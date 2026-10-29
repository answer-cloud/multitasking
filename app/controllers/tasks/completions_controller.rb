# frozen_string_literal: true

module Tasks
  # Checking a task off, and unchecking it.
  #
  # A singular resource under the task rather than a `done` flag on update, so
  # the request says what happened. Both actions set absolute state, so a
  # double-click or a retried request lands in the same place.
  class CompletionsController < ApplicationController
    before_action :set_task

    def create
      authorize @task, :complete?
      @task.complete! unless @task.done?

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to dashboard_path, status: :see_other }
      end
    end

    def destroy
      authorize @task, :complete?
      @task.reopen! if @task.done?

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: dashboard_path, status: :see_other }
      end
    end

    private

    def set_task
      @task = current_team.tasks.find(params[:task_id])
    end
  end
end
