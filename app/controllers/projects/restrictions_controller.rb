# frozen_string_literal: true

module Projects
  # Keeping a project to the team's admins, and handing it back to everybody.
  #
  # Not the same as hiding: hiding takes a project off your own list and is
  # yours alone; this takes it, and every task filed under it, away from
  # everybody who is not an admin. A singular resource under the project, like
  # its hiding, so the request says what happened. Both actions set absolute
  # state, so a double-click lands in the same place.
  class RestrictionsController < ApplicationController
    before_action :set_project

    def create
      authorize @project, :restrict?
      @project.restrict!

      redirect_back fallback_location: projects_path, notice: "#{@project.name} is now for admins only.", status: :see_other
    end

    def destroy
      authorize @project, :restrict?
      @project.share!

      redirect_back fallback_location: projects_path, notice: "#{@project.name} is back with the whole team.", status: :see_other
    end

    private

    def set_project
      @project = policy_scope(current_team.projects).find(params[:project_id])
    end
  end
end
