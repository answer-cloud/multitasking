# frozen_string_literal: true

# How to plug Claude Code, Codex and Slack into the team's inbox.
#
# Any member may see the token: it only lets a hook add tasks to this team,
# which any member can already do by typing. Rotating it breaks every hook that
# uses it, so that takes an admin.
class ConnectionsController < ApplicationController
  def show
    authorize current_team, :show?, policy_class: TeamPolicy
    @slack = current_team.slack_connections.find_by(user: current_user)
  end

  def update
    authorize current_team, :update?, policy_class: TeamPolicy
    current_team.regenerate_inbox_token

    redirect_to connection_path, notice: "New token made. Update your hook config with it."
  end
end
