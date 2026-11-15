# frozen_string_literal: true

# The team at a glance: everybody on it, how much each has on, and a way into
# each person's list. A person here is a membership — somebody as they are on
# this team — so the id in the address means nothing on another one.
class PeopleController < ApplicationController
  include TaskList

  # How many of a person's tasks their card shows before "and 4 more".
  PREVIEW = 3

  def index
    @memberships = policy_scope(scoped_memberships.ordered.includes(:user))
    pending = policy_scope(current_team.tasks).pending.in_order.includes(:project).group_by(&:assignee_id)

    @pending = pending.except(nil)
    @unassigned = pending.fetch(nil, [])
    @done_today = policy_scope(current_team.tasks).done_today.group(:assignee_id).count
  end

  def show
    @membership = scoped_memberships.find(params[:id])
    authorize @membership

    load_task_list(@membership.user)
    render "dashboard/show"
  end

  private

  # The one line that matters.
  def scoped_memberships = current_team.memberships
end
