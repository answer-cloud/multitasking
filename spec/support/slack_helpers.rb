# frozen_string_literal: true

# Slack test support. Events are signed with Slack's real algorithm, the way
# Stripe webhooks are in stripe_helpers.rb: a stubbed check would keep passing
# if the check were deleted.
module SlackHelpers
  SIGNING_SECRET = "slack-signing-secret"

  def with_slack_configured
    allow(Rails.configuration.x).to receive_messages(slack_client_id: "123.456", slack_client_secret: "slack-client-secret",
                                                     slack_signing_secret: SIGNING_SECRET)
  end

  def slack_headers(body, secret: SIGNING_SECRET, at: Time.current)
    timestamp = at.to_i.to_s
    signature = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "v0:#{timestamp}:#{body}")}"
    { "X-Slack-Request-Timestamp" => timestamp, "X-Slack-Signature" => signature, "Content-Type" => "application/json" }
  end

  # Answers one Web API method with `body`, merged into `ok: true`.
  def slack_answers(method, ok: true, **body)
    stub_request(:post, "https://slack.com/api/#{method}")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { ok: ok }.merge(body).to_json)
  end
end
