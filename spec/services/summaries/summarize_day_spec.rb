# frozen_string_literal: true

require "rails_helper"

RSpec.describe Summaries::SummarizeDay do
  include ActiveSupport::Testing::TimeHelpers

  let(:team) { create(:team, time_zone: "Pacific Time (US & Canada)") }
  let(:day) { Date.new(2026, 11, 2) }
  let(:evening) { Time.find_zone("Pacific Time (US & Canada)").local(2026, 11, 2, 21, 0) }
  let(:messages_url) { %r{\Ahttps://api\.anthropic\.com/v1/messages} }

  around { |example| travel_to(evening) { example.run } }

  before { allow(Rails.configuration.x).to receive(:anthropic_api_key).and_return("sk-ant-test") }

  def claude_says(text, stop_reason: "end_turn")
    stub_request(:post, messages_url).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        id: "msg_test", type: "message", role: "assistant", model: "claude-opus-5-5",
        content: [ { type: "text", text: text } ],
        stop_reason: stop_reason, stop_sequence: nil,
        usage: { input_tokens: 10, output_tokens: 20 }
      }.to_json
    )
  end

  def finish(title, at:, project: nil)
    create(:task, team: team, title: title, project: project, completed_at: at)
  end

  describe "writing a day" do
    it "keeps what Claude wrote, with the number of tasks it covered" do
      claude_says("A Storefront day.")
      finish("Send the invoice", at: evening - 3.hours)
      finish("Book the dentist", at: evening - 1.hour)

      summary = described_class.call(team: team, day: day).value

      expect(summary).to have_attributes(day: day, body: "A Storefront day.", task_count: 2, team: team)
    end

    it "cuts the day in the team's zone, not UTC" do
      claude_says("Late one.")
      # 11pm in California is already tomorrow in UTC.
      finish("Late night fix", at: evening + 2.hours)
      # And 1am UTC on the 2nd was still the 1st here.
      finish("Yesterday's", at: Time.utc(2026, 11, 2, 1, 0))

      expect(described_class.call(team: team, day: day).value.task_count).to eq(1)
    end

    it "sends the tasks as fenced data, with their projects, and turns fallbacks on" do
      claude_says("Fine.")
      project = create(:project, team: team, name: "Storefront")
      finish("Send the invoice", at: evening - 2.hours, project: project)

      described_class.call(team: team, day: day)

      expect(WebMock).to(have_requested(:post, messages_url).with { |request|
        body = JSON.parse(request.body)
        body["model"] == "claude-opus-5-5" &&
          body["fallbacks"] == "default" &&
          body.dig("messages", 0, "content").include?("<tasks>\n- [Storefront] Send the invoice (19:00)\n</tasks>")
      })
    end

    it "never reads another team's tasks" do
      claude_says("Fine.")
      finish("Ours", at: evening - 1.hour)
      create(:task, team: create(:team), title: "Theirs", completed_at: evening - 1.hour)

      described_class.call(team: team, day: day)

      expect(WebMock).to(have_requested(:post, messages_url).with { |request| request.body.exclude?("Theirs") })
    end
  end

  describe "idempotency" do
    it "writes one summary however many times it runs, and asks Claude once" do
      claude_says("Once.")
      finish("Send the invoice", at: evening - 1.hour)

      2.times { described_class.call(team: team, day: day) }

      expect(team.daily_summaries.count).to eq(1)
      expect(WebMock).to have_requested(:post, messages_url).once
    end
  end

  describe "days it leaves alone" do
    it "makes no call for a day with nothing done" do
      expect(described_class.call(team: team, day: day).value).to eq(:nothing_done)
      expect(WebMock).not_to have_requested(:post, messages_url)
    end

    it "makes no call when no key is configured" do
      allow(Rails.configuration.x).to receive(:anthropic_api_key).and_return(nil)
      finish("Send the invoice", at: evening - 1.hour)

      expect(described_class.call(team: team, day: day).value).to eq(:not_configured)
      expect(WebMock).not_to have_requested(:post, messages_url)
    end

    it "writes nothing when every model declines" do
      claude_says("", stop_reason: "refusal")
      finish("Send the invoice", at: evening - 1.hour)

      expect(described_class.call(team: team, day: day)).to be_failure
      expect(team.daily_summaries).to be_empty
    end

    it "fails, rather than retrying forever, when the key is wrong" do
      stub_request(:post, messages_url).to_return(
        status: 401, headers: { "Content-Type" => "application/json" },
        body: { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } }.to_json
      )
      finish("Send the invoice", at: evening - 1.hour)

      expect(described_class.call(team: team, day: day)).to be_failure
      expect(team.daily_summaries).to be_empty
    end
  end
end
