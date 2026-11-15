# frozen_string_literal: true

module Tasks
  # Filing a task under a project, from the picker in the task's row.
  #
  # A singular resource under the task, like the completion, so the request
  # says what happened. Unlike an edit it is not activity: sorting the list is
  # not working on the task, and a quiet task should stay quiet.
  class ProjectsController < ApplicationController
    before_action :set_task

    def update
      authorize @task, :update?
      @task.update!(project: chosen_project)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: @task, status: :see_other }
      end
    end

    private

    def set_task
      @task = policy_scope(current_team.tasks).find(params[:task_id])
    end

    # Looked up through the team, so another team's project is not found —
    # nor is one kept to admins, for anybody else. A blank choice takes the
    # task out of its project.
    def chosen_project
      id = params.dig(:task, :project_id).presence
      visible_projects.find(id) if id
    end
  end
end
