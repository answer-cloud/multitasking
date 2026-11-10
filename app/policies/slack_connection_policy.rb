# frozen_string_literal: true

# A Slack connection is one person's own: it reads their messages. Any member
# may link their Slack to the team, and only they may unlink it — not an admin,
# and nobody while impersonating.
class SlackConnectionPolicy < ApplicationPolicy
  def create?  = member? && !impersonating?
  def destroy? = member? && !impersonating? && record.user_id == user&.id
  def update?  = false
end
