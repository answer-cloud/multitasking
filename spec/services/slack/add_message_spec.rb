# frozen_string_literal: true

require "rails_helper"

RSpec.describe Slack::AddMessage do
  let(:tenant) { create_tenant }
  let(:connection) { create(:slack_connection, team: tenant.team, user: tenant.member) }
  let(:permalink) { "https://acme.slack.com/archives/C1/p17120001" }

  def message_says(text, ts: "1712.0001")
    slack_answers("conversations.history", messages: [ { ts: ts, text: text, user: "U9" } ])
    slack_answers("chat.getPermalink", permalink: permalink)
  end

  def add = described_class.call(connection: connection, channel: "C1", ts: "1712.0001")

  it "adds the message to the team's list, linked back to Slack" do
    message_says("Send Sam the contract &amp; the invoice")

    task = add.value

    expect(task).to have_attributes(team: tenant.team, source: "slack", external_id: "C1-1712.0001",
                                    title: "Send Sam the contract & the invoice", notes: nil, url: permalink,
                                    created_by: tenant.member)
    expect(task.link).to eq(permalink)
  end

  it "reads Slack's markup the way a person would" do
    message_says("<@U9> can you check <https://example.com/pr/1|the PR> in <#C2|design> before <!here> sees it?")
    slack_answers("users.info", user: { profile: { display_name: "Sam", real_name: "Sam Smith" } })

    expect(add.value.title).to eq("@Sam can you check the PR in #design before @here sees it?")
  end

  it "titles a long message with its opening and keeps the rest in the notes" do
    message_says("Plan the offsite\nBook the venue\nSort the travel")

    task = add.value

    expect(task.title).to eq("Plan the offsite")
    expect(task.notes).to eq("Plan the offsite\nBook the venue\nSort the travel")
  end

  it "finds a reply inside a thread" do
    slack_answers("conversations.history", messages: [])
    slack_answers("conversations.replies", messages: [ { ts: "1711.0000", text: "Parent" }, { ts: "1712.0001", text: "The reply" } ])
    slack_answers("chat.getPermalink", permalink: permalink)

    expect(add.value.title).to eq("The reply")
  end

  it "asks for the thread a pasted link names" do
    slack_answers("conversations.history", messages: [])
    replies = slack_answers("conversations.replies", messages: [ { ts: "1711.0000", text: "Parent" }, { ts: "1712.0001", text: "The reply" } ])
    slack_answers("chat.getPermalink", permalink: permalink)

    described_class.call(connection: connection, channel: "C1", ts: "1712.0001", thread_ts: "1711.0000")

    expect(replies.with(body: hash_including("ts" => "1711.0000", "oldest" => "1712.0001"))).to have_been_requested
  end

  it "files the message under the project it is given" do
    message_says("Send the contract")
    project = create(:project, team: tenant.team)

    task = described_class.call(connection: connection, channel: "C1", ts: "1712.0001", project: project).value

    expect(task.project).to eq(project)
  end

  it "leaves a message already on the list alone, so a redelivery changes nothing" do
    message_says("Send the contract")
    task = add.value
    task.update!(title: "Send the contract, edited")

    expect { add }.not_to change { task.reload.attributes }
    expect(tenant.team.tasks.count).to eq(1)
  end

  it "brings a ticked-off message back to the top when it is pinned again" do
    message_says("Send the contract")
    task = add.value
    task.complete!
    other = create(:task, team: tenant.team)

    add

    expect(task.reload).not_to be_done
    expect(task.position).to be < other.reload.position
  end

  it "drops a connection whose token Slack has revoked" do
    slack_answers("conversations.history", ok: false, error: "token_revoked")

    result = add

    expect(result).to be_failure
    expect(SlackConnection.exists?(connection.id)).to be(false)
  end

  it "lets the job retry when Slack is busy" do
    stub_request(:post, "https://slack.com/api/conversations.history").to_return(status: 429)

    expect { add }.to raise_error(Slack::Api::Unavailable)
  end
end
