# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connections" do
  let(:tenant) { create_tenant }

  it "shows a member their own inbox token and the hook setup, and nobody else's token" do
    sign_in tenant.member

    get connection_path

    expect(response.body).to include(tenant.member.membership_for(tenant.team).inbox_token)
    expect(response.body).not_to include(tenant.owner.membership_for(tenant.team).inbox_token)
    expect(response.body).to include(agent_hook_url)
    expect(response.body).to include("~/.config/multitasking/agent-hook claude")
    expect(response.body).to include("AskUserQuestion|ExitPlanMode")
    expect(response.body).not_to include(Rails.root.to_s)
  end

  it "serves the hook script to a signed-out curl" do
    get agent_hook_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(Rails.root.join("script/agent-hook").binread)
  end

  it "offers the save-this-tab bookmarklet, pointed at this app" do
    sign_in tenant.member

    get connection_path

    expect(response.body).to include("href=\"javascript:")
    expect(response.body).to include(CGI.escapeHTML(new_task_url.to_json))
  end

  it "serves the assign skill to a signed-out curl" do
    get agent_skill_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(Rails.root.join("script/assign-skill.md").binread)
  end

  it "shows how to teach Claude to assign, pointed at this app" do
    sign_in tenant.member

    get connection_path

    expect(response.body).to include(agent_skill_url)
    expect(response.body).to include("~/.claude/skills/done-assign/SKILL.md")
  end

  it "lets a member rotate their own token, which retires the old one and leaves everybody else's alone" do
    sign_in tenant.member
    membership = tenant.member.membership_for(tenant.team)
    old = membership.inbox_token
    owners = tenant.owner.membership_for(tenant.team).inbox_token

    patch connection_path

    expect(membership.reload.inbox_token).not_to eq(old)
    expect(tenant.owner.membership_for(tenant.team).inbox_token).to eq(owners)
    post inbox_tasks_path, params: { title: "Stale" }, headers: { "Authorization" => "Bearer #{old}" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
