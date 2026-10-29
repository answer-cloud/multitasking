# frozen_string_literal: true

# The front door: what is left to do, and what has already gone in the jar
# today.
class DashboardController < ApplicationController
  def show
    authorize current_team, :show?, policy_class: TeamPolicy

    # Everything here starts from the team, not from the model class.
    @tasks = policy_scope(current_team.tasks.pending.fresh_first.includes(:created_by))
    @done_today = policy_scope(current_team.tasks.done_today.recently_done)
    @new_task = current_team.tasks.new
  end
end
