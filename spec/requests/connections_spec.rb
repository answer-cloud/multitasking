# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connections" do
  let(:tenant) { create_tenant }

  it "shows any member the team's inbox token and the hook setup" do
    sign_in tenant.member

    get connection_path

    expect(response.body).to include(tenant.team.inbox_token)
    expect(response.body).to include("script/agent-hook")
  end

  it "does not let a member rotate the token" do
    sign_in tenant.member

    expect { patch connection_path }.not_to change { tenant.team.reload.inbox_token }
  end

  it "lets an owner rotate the token, which retires the old one" do
    sign_in tenant.owner
    old = tenant.team.inbox_token

    patch connection_path

    expect(tenant.team.reload.inbox_token).not_to eq(old)
    post inbox_tasks_path, params: { title: "Stale" }, headers: { "Authorization" => "Bearer #{old}" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
