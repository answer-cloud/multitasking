# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hiding projects" do
  let(:tenant) { create_tenant }
  let(:membership) { tenant.team.memberships.find_by!(user: tenant.member) }
  let!(:project) { create(:project, team: tenant.team, name: "Storefront") }

  before { sign_in tenant.member }

  describe "hiding" do
    it "takes the project's tasks off the dashboard, priorities and all" do
      create(:task, team: tenant.team, project: project, title: "Hidden away")
      create(:task, team: tenant.team, project: project, title: "Starred but hidden").prioritize!
      create(:task, team: tenant.team, title: "Unfiled")

      post project_hiding_path(project)
      get dashboard_path

      expect(response.body).not_to include("Hidden away")
      expect(response.body).not_to include("Starred but hidden")
      expect(response.body).to include("Unfiled")
    end

    it "leaves the project's tasks off the by-project view too" do
      create(:task, team: tenant.team, project: project, title: "Hidden away")
      membership.hide!(project)

      get dashboard_path(view: "projects")

      expect(Nokogiri::HTML(response.body).at_css(%(.task-group[data-project-id="#{project.id}"]))).to be_nil
    end

    it "still counts its tasks finished today, since the jar is everything" do
      create(:task, :done, team: tenant.team, project: project, title: "Done anyway")
      membership.hide!(project)

      get dashboard_path

      expect(response.body).to include("Done anyway")
    end

    it "lists it under the switch with a way back" do
      membership.hide!(project)

      get dashboard_path

      hidden = Nokogiri::HTML(response.body).at_css(".hidden-projects")
      expect(hidden.text).to include("Storefront")
      expect(hidden.at_css(%(form[action="#{project_hiding_path(project)}"]))).to be_present
    end

    it "is safe to send twice" do
      post project_hiding_path(project)
      post project_hiding_path(project)

      expect(membership.reload.hidden_project_ids).to eq([ project.id ])
    end

    # The list is the team's. One person hiding a project must not take it
    # off anyone else's dashboard.
    it "hides it for you alone" do
      create(:task, team: tenant.team, project: project, title: "Still theirs")
      post project_hiding_path(project)

      sign_in tenant.owner
      get dashboard_path

      expect(response.body).to include("Still theirs")
    end

    it "cannot reach another team's project" do
      other = create_tenant
      theirs = create(:project, team: other.team)

      post project_hiding_path(theirs)

      expect(response).to have_http_status(:not_found)
      expect(membership.reload.hidden_project_ids).to be_empty
    end
  end

  describe "showing again" do
    it "puts the project's tasks back on the dashboard" do
      create(:task, team: tenant.team, project: project, title: "Back again")
      membership.hide!(project)

      delete project_hiding_path(project)
      get dashboard_path

      expect(response.body).to include("Back again")
      expect(membership.reload.hidden_project_ids).to be_empty
    end
  end

  describe "the projects page" do
    it "offers to hide a shown project and to show a hidden one" do
      other = create(:project, team: tenant.team, name: "Backoffice")
      membership.hide!(other)

      get projects_path

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(%(form[action="#{project_hiding_path(project)}"] button))["aria-label"]).to eq("Hide Storefront on your list")
      expect(page.at_css(%(form[action="#{project_hiding_path(other)}"] button))["aria-label"]).to eq("Show Backoffice on your list")
    end
  end
end
