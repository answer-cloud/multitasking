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
    waiting, listed = policy_scope(current_team.tasks).pending.in_order.includes(:project).partition(&:invitation_id)

    @pending = listed.group_by(&:assignee_id)
    @unassigned = @pending.delete(nil) || []
    @waiting = waiting.group_by(&:invitation_id)
    @invitations = invitations_to_show
    @done_today = policy_scope(current_team.tasks).done_today.group(:assignee_id).count
  end

  def show
    @membership = scoped_memberships.find(params[:id])
    authorize @membership

    load_task_list(@membership.user)
    render "dashboard/show"
  end

  private

  # The people asked onto the team who have not joined yet: you can give
  # them tasks now, and the tasks are theirs when they accept. An invitation
  # that ran out stays for as long as tasks wait on it. Only for those who
  # may see invitations at all — the policy scope is empty for the rest.
  def invitations_to_show
    policy_scope(current_team.invitations).unaccepted.order(:email)
      .select { |invitation| invitation.pending? || @waiting.key?(invitation.id) }
  end

  # The one line that matters.
  def scoped_memberships = current_team.memberships
end
