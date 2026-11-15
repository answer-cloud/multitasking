# frozen_string_literal: true

# How to plug Claude Code, Codex and Slack into the team's inbox.
#
# The token is your own: it is what puts a hook's tasks on your list rather
# than a colleague's. It only lets a hook add tasks to this team, which you
# can already do by typing. Rotating it breaks nobody's hooks but yours, so
# anybody may rotate their own.
class ConnectionsController < ApplicationController
  def show
    authorize current_team, :show?, policy_class: TeamPolicy
    @slack = current_team.slack_connections.find_by(user: current_user)
  end

  def update
    authorize current_team, :show?, policy_class: TeamPolicy
    current_membership.regenerate_inbox_token

    redirect_to connection_path, notice: "New token made. Update your hook config with it."
  end
end
