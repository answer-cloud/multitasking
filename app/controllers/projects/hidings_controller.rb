# frozen_string_literal: true

module Projects
  # Keeping a project's tasks off your dashboard, and letting them back on.
  #
  # A singular resource under the project, like a task's priority, so the
  # request says what happened. It is kept on your membership, not the
  # project: the list is the team's, and hiding is only about your view of it.
  # Both actions set absolute state, so a double-click lands in the same place.
  class HidingsController < ApplicationController
    before_action :set_project

    def create
      authorize @project, :hide?
      current_membership.hide!(@project)

      redirect_back fallback_location: dashboard_path, notice: "#{@project.name} hidden from your list.", status: :see_other
    end

    def destroy
      authorize @project, :hide?
      current_membership.unhide!(@project)

      redirect_back fallback_location: dashboard_path, notice: "#{@project.name} back on your list.", status: :see_other
    end

    private

    def set_project
      @project = current_team.projects.find(params[:project_id])
    end
  end
end
