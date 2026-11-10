# frozen_string_literal: true

require "rails_helper"

RSpec.describe Slack::AddMessageJob do
  let(:tenant) { create_tenant }
  let!(:connection) { create(:slack_connection, team: tenant.team, user: tenant.member, slack_user_id: "U1") }

  before do
    slack_answers("conversations.history", messages: [ { ts: "1712.0001", text: "Call the bank" } ])
    slack_answers("chat.getPermalink", permalink: "https://acme.slack.com/archives/C1/p17120001")
  end

  it "adds the pin to the team of the person who pinned it" do
    described_class.perform_now("T0TEAM", "U1", "C1", "1712.0001")

    expect(tenant.team.tasks.pluck(:title)).to eq([ "Call the bank" ])
  end

  it "does nothing for a Slack account nobody connected" do
    described_class.perform_now("T0TEAM", "U-stranger", "C1", "1712.0001")

    expect(Task.count).to eq(0)
  end

  it "stops filling the list of a team its person has left" do
    tenant.member.memberships.find_by(team: tenant.team).destroy!

    described_class.perform_now("T0TEAM", "U1", "C1", "1712.0001")

    expect(Task.count).to eq(0)
  end
end
