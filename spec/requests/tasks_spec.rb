# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tasks" do
  describe "cross-team isolation" do
    it_behaves_like "a tenant-isolated resource" do
      let(:factory) { :task }
      let(:member_path) { ->(record) { task_path(record) } }
      let(:collection_path) { tasks_path }
      let(:update_params) { { task: { title: "Hijacked" } } }
    end

    # The shared example only checks listing for records with a `name`. Tasks
    # have a title, so both lists are checked here by hand.
    it "never shows another team's tasks on the dashboard or in the done pile" do
      mine = create_tenant
      theirs = create_tenant
      create(:task, team: theirs.team, title: "Their open secret")
      create(:task, :done, team: theirs.team, title: "Their finished secret")

      sign_in mine.owner

      get dashboard_path
      expect(response.body).not_to include("Their open secret")
      expect(response.body).not_to include("Their finished secret")

      get tasks_path
      expect(response.body).not_to include("Their finished secret")
    end
  end

  describe "quick add" do
    let(:tenant) { create_tenant }

    before { sign_in tenant.member }

    it "assigns the task to the active team, never to a team from params" do
      other = create_tenant

      # Even if a team_id is smuggled in, the task belongs to the active team:
      # it is built from current_team.tasks and team_id is not permitted.
      post tasks_path, params: { task: { title: "Smuggled", team_id: other.team.id } }

      expect(Task.find_by(title: "Smuggled").team).to eq(tenant.team)
    end

    it "records who added it" do
      post tasks_path, params: { task: { title: "Attributed" } }

      expect(Task.find_by(title: "Attributed").created_by).to eq(tenant.member)
    end

    it "keeps a spoken task marked as spoken" do
      post tasks_path, params: { task: { title: "Said aloud", source: "voice" } }

      expect(Task.find_by(title: "Said aloud").source).to eq("voice")
    end

    # Only hooks with the inbox token may claim to be Claude or Codex; a form
    # post that says so is just someone typing.
    it "refuses to let the form claim an agent as the source" do
      post tasks_path, params: { task: { title: "Pretend agent", source: "claude" } }

      expect(Task.find_by(title: "Pretend agent").source).to eq("typed")
    end

    it "prepends the new task to the list as a Turbo Stream" do
      post tasks_path, params: { task: { title: "Streamed" } }, as: :turbo_stream

      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include(%(action="prepend" target="tasks"))
      expect(response.body).to include("Streamed")
    end

    it "says what went wrong without leaving the page when the title is blank" do
      post tasks_path, params: { task: { title: "" } }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Title can&#39;t be blank")
    end
  end

  describe "editing" do
    let(:tenant) { create_tenant }
    let!(:task) { create(:task, team: tenant.team, last_activity_at: 3.days.ago) }

    before { sign_in tenant.member }

    it "counts an edit as activity, so the task is no longer quiet" do
      patch task_path(task), params: { task: { title: "Renamed" } }

      expect(task.reload.title).to eq("Renamed")
      expect(task).not_to be_quiet
    end

    it "refuses a link that is not http or https" do
      patch task_path(task), params: { task: { url: "javascript:alert(1)" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(task.reload.url).to be_nil
    end
  end

  describe "deleting" do
    let(:tenant) { create_tenant }
    let!(:task) { create(:task, team: tenant.team) }

    it "lets any member delete a task" do
      sign_in tenant.member

      delete task_path(task)

      expect(Task.exists?(task.id)).to be(false)
    end
  end

  describe "the done pile" do
    let(:tenant) { create_tenant }

    before { sign_in tenant.member }

    it "lists finished tasks and leaves open ones on the dashboard" do
      create(:task, :done, team: tenant.team, title: "Shipped it")
      create(:task, team: tenant.team, title: "Still going")

      get tasks_path

      expect(response.body).to include("Shipped it")
      expect(response.body).not_to include("Still going")
    end

    it "searches within the team only" do
      theirs = create_tenant
      create(:task, :done, team: tenant.team, title: "Alpha report")
      create(:task, :done, team: theirs.team, title: "Alpha secret")

      get tasks_path, params: { q: "Alpha" }

      expect(response.body).to include("Alpha report")
      expect(response.body).not_to include("Alpha secret")
    end
  end
end
