# frozen_string_literal: true

module Slack
  # Finishes "Connect Slack": trades the code Slack sent back for a user token
  # and links that Slack account to this person on this team.
  #
  # A Slack account feeds one team. Connecting it again from another team, or
  # as another person who signed in to that Slack account, moves it there —
  # signing in to Slack is the proof that it is theirs to move. The lookup is
  # by Slack's ids rather than through the team for exactly that reason.
  class Connect < ApplicationService
    def initialize(team:, user:, code:, redirect_uri:)
      @team = team
      @user = user
      @code = code
      @redirect_uri = redirect_uri
    end

    def call
      grant = Slack::Api.new.call("oauth.v2.access", client_id: config.slack_client_id, client_secret: config.slack_client_secret,
                                                     code: @code, redirect_uri: @redirect_uri)
      authed = grant["authed_user"].to_h
      return failure("Slack did not give Done access to your messages.") if authed["access_token"].blank?

      success(link(grant, authed))
    rescue Slack::Api::Error
      failure("Slack did not connect. Try again.")
    end

    private

    def link(grant, authed)
      SlackConnection.transaction do
        connection = SlackConnection.find_or_initialize_by(slack_team_id: grant.dig("team", "id"), slack_user_id: authed["id"])
        @team.slack_connections.where(user: @user).where.not(id: connection.id).destroy_all

        connection.update!(team: @team, user: @user, slack_team_name: grant.dig("team", "name"), access_token: authed["access_token"])
        connection
      end
    end

    def config = Rails.configuration.x
  end
end
