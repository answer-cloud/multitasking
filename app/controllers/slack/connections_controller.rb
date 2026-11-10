# frozen_string_literal: true

module Slack
  # "Connect Slack" on the connections page. The person signs in to Slack,
  # Slack sends them back to #callback with a code, and Slack::Connect trades
  # it for their token.
  #
  # A random `state` rides along and must come back unchanged. Without it,
  # anybody could send you a link that finishes *their* Slack sign-in inside
  # your account, and their pins would land on your list.
  class ConnectionsController < ApplicationController
    # Linking somebody's Slack is not something support staff do for them.
    before_action :block_while_impersonating!

    USER_SCOPES = %w[reactions:read channels:history groups:history im:history mpim:history users:read].freeze

    def create
      authorize current_team.slack_connections.new(user: current_user)
      return redirect_to(connection_path, alert: "Slack is not set up on this server yet.") unless SlackConnection.configured?

      session[:slack_state] = SecureRandom.urlsafe_base64(32)
      redirect_to "https://slack.com/oauth/v2/authorize?#{{ client_id: Rails.configuration.x.slack_client_id,
                                                           user_scope: USER_SCOPES.join(","),
                                                           redirect_uri: callback_slack_connection_url,
                                                           state: session[:slack_state] }.to_query}",
                  allow_other_host: true
    end

    def callback
      authorize current_team.slack_connections.new(user: current_user), :create?
      return redirect_to(connection_path, alert: "Slack was not connected.") unless state_matches? && params[:code].present?

      result = Slack::Connect.call(team: current_team, user: current_user, code: params[:code].to_s, redirect_uri: callback_slack_connection_url)

      if result.success?
        redirect_to connection_path, notice: "Slack is connected. Pin a message with 📌 and it lands here."
      else
        redirect_to connection_path, alert: result.error
      end
    end

    def destroy
      connection = current_team.slack_connections.find_by!(user: current_user)
      authorize connection

      revoke(connection)
      connection.destroy!
      redirect_to connection_path, notice: "Slack is disconnected."
    end

    private

    def state_matches?
      expected = session.delete(:slack_state).to_s
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
    end

    # Tells Slack to retire the token too, so it is not left working somewhere.
    # If Slack is out of reach the token still goes from here, and Slack lists
    # the app under the person's own authorizations to remove by hand.
    def revoke(connection)
      Slack::Api.new(connection.access_token).call("auth.revoke")
    rescue Slack::Api::Error
      nil
    end
  end
end
