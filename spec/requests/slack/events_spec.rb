# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Slack events" do
  include ActiveJob::TestHelper

  before { with_slack_configured }

  def deliver(payload, headers: nil)
    body = payload.to_json
    post slack_events_path, params: body, headers: headers || slack_headers(body)
  end

  def reaction(emoji: "pushpin", type: "reaction_added", item_type: "message")
    {
      type: "event_callback", team_id: "T0TEAM", event_id: "Ev1",
      event: { type: type, user: "U000001", reaction: emoji, item: { type: item_type, channel: "C1", ts: "1712.0001" } }
    }
  end

  it "answers Slack's url_verification challenge" do
    deliver({ type: "url_verification", challenge: "abc123" })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("challenge" => "abc123")
  end

  it "queues a pinned message" do
    expect { deliver(reaction) }.to have_enqueued_job(Slack::AddMessageJob).with("T0TEAM", "U000001", "C1", "1712.0001")

    expect(response).to have_http_status(:ok)
  end

  it "ignores every other emoji, removals, and reactions to files" do
    expect {
      deliver(reaction(emoji: "thumbsup"))
      deliver(reaction(type: "reaction_removed"))
      deliver(reaction(item_type: "file"))
    }.not_to have_enqueued_job(Slack::AddMessageJob)

    expect(response).to have_http_status(:ok)
  end

  describe "signature" do
    it "refuses an unsigned request" do
      expect { deliver(reaction, headers: { "Content-Type" => "application/json" }) }.not_to have_enqueued_job

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses one signed with another secret" do
      body = reaction.to_json

      deliver(reaction, headers: slack_headers(body, secret: "not-ours"))

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a body changed after signing" do
      headers = slack_headers(reaction.to_json)

      deliver(reaction(emoji: "pushpin").merge(team_id: "T0OTHER"), headers: headers)

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a replay older than five minutes" do
      body = reaction.to_json

      deliver(reaction, headers: slack_headers(body, at: 6.minutes.ago))

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses everything while Slack is not set up" do
      allow(Rails.configuration.x).to receive(:slack_signing_secret).and_return(nil)
      body = reaction.to_json

      deliver(reaction, headers: slack_headers(body, secret: ""))

      expect(response).to have_http_status(:bad_request)
    end
  end
end
