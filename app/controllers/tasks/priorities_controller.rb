# frozen_string_literal: true

module Tasks
  # Making a task a priority, which moves it up into the priority list above
  # the rest, and letting it back down.
  #
  # A singular resource under the task, like the completion, so the request
  # says what happened. Both actions set absolute state, so a double-click or
  # a retried request lands in the same place.
  class PrioritiesController < ApplicationController
    before_action :set_task

    def create
      authorize @task, :update?
      @task.prioritize! unless @task.priority? || @task.done?

      respond_to do |format|
        format.turbo_stream { render :move }
        format.html { redirect_back fallback_location: dashboard_path, status: :see_other }
      end
    end

    def destroy
      authorize @task, :update?
      @task.deprioritize! if @task.priority?

      respond_to do |format|
        format.turbo_stream { render :move }
        format.html { redirect_back fallback_location: dashboard_path, status: :see_other }
      end
    end

    private

    def set_task
      @task = current_team.tasks.find(params[:task_id])
    end
  end
end
