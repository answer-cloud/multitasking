# frozen_string_literal: true

# The front door: what is left on your own list, and what has already gone in
# the jar today. A colleague's list is the same page; see PeopleController.
class DashboardController < ApplicationController
  include TaskList

  def show
    authorize current_team, :show?, policy_class: TeamPolicy

    load_task_list(Current.user, hidden_project_ids: current_membership.hidden_project_ids)
  end
end
