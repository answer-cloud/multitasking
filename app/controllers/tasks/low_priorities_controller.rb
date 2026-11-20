# frozen_string_literal: true

module Tasks
  # Putting a task off into the low priority list under the rest, and bringing
  # it back. The mirror of PrioritiesController, and it answers the same way:
  # out of one list and onto the top of another.
  #
  # Both actions set absolute state, so a double-click or a retried request
  # lands in the same place.
  class LowPrioritiesController < ApplicationController
    before_action :set_task

    def create
      authorize @task, :update?
      @task.low_prioritize! unless @task.low_priority? || @task.done?

      respond_to do |format|
        format.turbo_stream { render "tasks/priorities/move" }
        format.html { redirect_back fallback_location: dashboard_path, status: :see_other }
      end
    end

    def destroy
      authorize @task, :update?
      @task.deprioritize! if @task.low_priority?

      respond_to do |format|
        format.turbo_stream { render "tasks/priorities/move" }
        format.html { redirect_back fallback_location: dashboard_path, status: :see_other }
      end
    end

    private

    def set_task
      @task = policy_scope(current_team.tasks).find(params[:task_id])
    end
  end
end
