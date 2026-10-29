# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard" do
  it "requires authentication" do
    get dashboard_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "sends a user with no team to team creation" do
    sign_in create(:user)

    get dashboard_path
    expect(response).to redirect_to(new_team_path)
  end

  it "renders the active team" do
    tenant = create_tenant(name: "Northwind")
    sign_in tenant.owner

    get dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Northwind")
  end

  it "shows what is left to do and what went in the jar today" do
    tenant = create_tenant
    create(:task, team: tenant.team, title: "Still to do")
    create(:task, :done, team: tenant.team, title: "Finished today")
    create(:task, team: tenant.team, completed_at: 2.days.ago, title: "Finished last week")
    sign_in tenant.owner

    get dashboard_path

    expect(response.body).to include("Still to do")
    expect(response.body).to include("Finished today")
    expect(response.body).not_to include("Finished last week")
  end
end
