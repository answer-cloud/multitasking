# frozen_string_literal: true

module Slack
  # Adds one pinned Slack message to its person's team. Safe to run more than
  # once: Slack::AddMessage leaves a message that is already on the list alone.
  class AddMessageJob < ApplicationJob
    queue_as :default

    retry_on Slack::Api::Unavailable, wait: :polynomially_longer, attempts: 5

    def perform(slack_team_id, slack_user_id, channel, ts)
      connection = SlackConnection.find_by(slack_team_id: slack_team_id, slack_user_id: slack_user_id)
      return if connection.nil?
      # Somebody who left the team keeps their Slack, not a line into the list.
      return unless connection.team.memberships.exists?(user: connection.user)

      Slack::AddMessage.call(connection: connection, channel: channel, ts: ts)
    end
  end
end
