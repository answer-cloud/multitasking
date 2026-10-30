# frozen_string_literal: true

module Tasks
  # Moving a task up or down the list, by dragging it there.
  #
  # The request says where it landed — its place counting from the top — not
  # how far it moved, so a retried request puts it in the same place. Like
  # filing it under a project, this is not activity: rearranging the list is
  # not working on the task.
  class PositionsController < ApplicationController
    before_action :set_task

    def update
      authorize @task, :update?
      @task.move_to(params.require(:position)) unless @task.done?

      head :no_content
    end

    private

    def set_task
      @task = current_team.tasks.find(params[:task_id])
    end
  end
end
