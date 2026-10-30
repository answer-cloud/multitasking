# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Projects" do
  describe "cross-team isolation" do
    it_behaves_like "a tenant-isolated resource" do
      let(:factory) { :project }
      let(:member_path) { ->(record) { project_path(record) } }
      let(:collection_path) { projects_path }
      let(:update_params) { { project: { name: "Hijacked" } } }
    end
  end

  describe "creating" do
    let(:tenant) { create_tenant }

    before { sign_in tenant.member }

    it "assigns the project to the active team, never to a team from params" do
      other = create_tenant

      # Even if a team_id is smuggled in, the project belongs to the active
      # team: it is built from current_team.projects and team_id is not
      # a permitted parameter.
      post projects_path, params: { project: { name: "Smuggled", team_id: other.team.id } }

      expect(Project.find_by(name: "Smuggled").team).to eq(tenant.team)
    end

    it "records who made it" do
      post projects_path, params: { project: { name: "Attributed", directory: "/code/attributed" } }

      project = Project.find_by(name: "Attributed")
      expect(project.created_by).to eq(tenant.member)
      expect(project.directory).to eq("/code/attributed")
    end

    it "saves the other names it is called" do
      post projects_path, params: { project: { name: "slater-suite", alias_list: "Slater, Slater Sweet" } }

      expect(Project.find_by(name: "slater-suite").aliases).to eq([ "Slater", "Slater Sweet" ])
    end

    it "re-renders with errors when invalid" do
      post projects_path, params: { project: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "the list" do
    let(:tenant) { create_tenant }

    before { sign_in tenant.member }

    it "counts what is still to do in each project" do
      project = create(:project, team: tenant.team, name: "Storefront")
      create_list(:task, 2, team: tenant.team, project: project)
      create(:task, :done, team: tenant.team, project: project)

      get projects_path

      expect(response.body).to include("Storefront")
      expect(response.body).to include(%(<td class="is-numeric">2</td>))
    end
  end

  describe "a project's page" do
    let(:tenant) { create_tenant }

    before { sign_in tenant.member }

    it "shows its open tasks and no one else's" do
      project = create(:project, team: tenant.team)
      create(:task, team: tenant.team, project: project, title: "Filed here")
      create(:task, team: tenant.team, title: "Filed nowhere")

      get project_path(project)

      expect(response.body).to include("Filed here")
      expect(response.body).not_to include("Filed nowhere")
    end

    it "shows its finished tasks too" do
      project = create(:project, team: tenant.team)
      create(:task, :done, team: tenant.team, project: project, title: "Shipped here")

      get project_path(project)

      expect(response.body).to include("Shipped here")
    end

    it "has no Open in Claude button" do
      project = create(:project, team: tenant.team, directory: "/code/api")

      get project_path(project)

      expect(response.body).not_to include("Open in Claude")
    end
  end

  describe "deleting" do
    let(:tenant) { create_tenant }

    before { sign_in tenant.member }

    it "keeps the project's tasks on the list" do
      project = create(:project, team: tenant.team)
      task = create(:task, team: tenant.team, project: project)

      delete project_path(project)

      expect(response).to redirect_to(projects_path)
      expect(task.reload.project).to be_nil
    end
  end
end
