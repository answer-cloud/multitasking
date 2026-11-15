# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Keeping a project to admins" do
  let(:tenant) { create_tenant }
  let!(:project) { create(:project, team: tenant.team, name: "Hiring") }

  describe "restricting" do
    it "lets an owner keep a project to admins, and hand it back" do
      sign_in tenant.owner

      post project_restriction_path(project)
      expect(project.reload).to be_admin_only

      delete project_restriction_path(project)
      expect(project.reload).not_to be_admin_only
    end

    it "lets an admin do the same" do
      admin = create(:user)
      create(:membership, :admin, user: admin, team: tenant.team)
      sign_in admin

      post project_restriction_path(project)

      expect(project.reload).to be_admin_only
    end

    it "does not let a member restrict a project, or see the control" do
      sign_in tenant.member

      post project_restriction_path(project)
      expect(project.reload).not_to be_admin_only

      get projects_path
      expect(response.body).not_to include(project_restriction_path(project))
    end

    # To a member, a restricted project is an id that was never issued — so
    # there is nothing to hand back, and nothing to learn by trying.
    it "does not let a member hand a restricted project back: it is not found" do
      project.restrict!
      sign_in tenant.member

      delete project_restriction_path(project)

      expect(response).to have_http_status(:not_found)
      expect(project.reload).to be_admin_only
    end

    it "cannot reach another team's project" do
      theirs = create(:project, team: create_tenant.team)
      sign_in tenant.owner

      post project_restriction_path(theirs)

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload).not_to be_admin_only
    end
  end

  describe "a restricted project, for a member" do
    let!(:task) { create(:task, team: tenant.team, assignee: tenant.member, project: project, title: "Call the candidate") }

    before do
      project.restrict!
      sign_in tenant.member
    end

    it "is gone from the projects page" do
      get projects_path

      expect(response.body).not_to include("Hiring")
    end

    it "returns 404 by its address, rather than 403" do
      get project_path(project)
      expect(response).to have_http_status(:not_found)

      patch project_path(project), params: { project: { name: "Guessed" } }
      expect(response).to have_http_status(:not_found)
      expect(project.reload.name).to eq("Hiring")
    end

    it "takes its tasks off their list, even ones with their name on" do
      get dashboard_path

      expect(response.body).not_to include("Call the candidate")
      expect(response.body).not_to include("Hiring")
    end

    it "takes its tasks off the team page and off a colleague's list" do
      create(:task, team: tenant.team, assignee: tenant.owner, project: project, title: "Draft the offer")

      get people_path
      expect(response.body).not_to include("Draft the offer")

      get person_path(tenant.owner.membership_for(tenant.team))
      expect(response.body).not_to include("Draft the offer")
    end

    it "returns 404 for its tasks, whatever is tried on them" do
      get task_path(task)
      expect(response).to have_http_status(:not_found)

      post task_completion_path(task)
      expect(response).to have_http_status(:not_found)
      expect(task.reload).not_to be_done

      delete task_path(task)
      expect(response).to have_http_status(:not_found)
    end

    it "is not offered in a picker, and cannot be picked by id" do
      mine = create(:task, team: tenant.team, assignee: tenant.member, title: "Unfiled")

      get dashboard_path
      expect(Nokogiri::HTML(response.body).css("select option").map(&:text)).not_to include("Hiring")

      patch task_project_path(mine), params: { task: { project_id: project.id } }
      expect(response).to have_http_status(:not_found)
      expect(mine.reload.project).to be_nil
    end

    it "is not found by quick add's leading name" do
      post tasks_path, params: { task: { title: "Hiring send the offer" } }

      expect(tenant.team.tasks.last).to have_attributes(title: "Hiring send the offer", project: nil)
    end
  end

  describe "a restricted project, for an admin" do
    before do
      project.restrict!
      create(:task, team: tenant.team, assignee: tenant.owner, project: project, title: "Draft the offer")
      sign_in tenant.owner
    end

    it "is still there, marked, with its tasks" do
      get projects_path
      expect(response.body).to include("Hiring")
      expect(response.body).to include("Admins only")

      get dashboard_path
      expect(response.body).to include("Draft the offer")
    end
  end
end
