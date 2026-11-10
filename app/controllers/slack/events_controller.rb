# frozen_string_literal: true

module Slack
  # Slack's Events API posts here. Like the Stripe webhook, it is thin on
  # purpose: verify, enqueue, answer within Slack's three seconds.
  #
  #   1. verify the signature — Slack signs every request with the app's
  #      signing secret; unsigned, tampered or stale requests get 400
  #   2. answer the url_verification challenge Slack sends once, at setup
  #   3. enqueue a pin, and ignore every other reaction
  #
  # There is no user and no team here. The job finds the connection from the
  # Slack ids in the event. A redelivered event enqueues a second job, which
  # finds the task already on the list and stops.
  class EventsController < ActionController::API
    # Slack's own advice: refuse anything older, so a captured request cannot
    # be replayed later.
    MAX_AGE = 5.minutes

    rate_limit to: 600, within: 1.minute, by: -> { request.remote_ip }

    def create
      return head :bad_request unless verified?

      payload = JSON.parse(request.raw_post)

      case payload["type"]
      when "url_verification" then render json: { challenge: payload["challenge"] }
      when "event_callback" then enqueue(payload) && head(:ok)
      else head :ok
      end
    end

    private

    def verified?
      secret = Rails.configuration.x.slack_signing_secret
      timestamp = request.headers["X-Slack-Request-Timestamp"].to_s
      signature = request.headers["X-Slack-Signature"].to_s
      return false if secret.blank? || timestamp !~ /\A\d+\z/ || (Time.current.to_i - timestamp.to_i).abs > MAX_AGE

      expected = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "v0:#{timestamp}:#{request.raw_post}")}"
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    def enqueue(payload)
      event = payload["event"].to_h
      item = event["item"].to_h
      pinned = event["type"] == "reaction_added" && event["reaction"] == SlackConnection::EMOJI && item["type"] == "message"

      Slack::AddMessageJob.perform_later(payload["team_id"].to_s, event["user"].to_s, item["channel"].to_s, item["ts"].to_s) if pinned
      true
    end
  end
end
