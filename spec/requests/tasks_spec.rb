# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tasks" do
  include ActiveSupport::Testing::TimeHelpers

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

  describe "saving a browser tab" do
    let(:tenant) { create_tenant }

    before { sign_in tenant.member }

    it "fills the form in from the bookmarklet without adding anything" do
      expect {
        get new_task_path, params: { title: "  Pricing \n page ", url: "https://example.com/pricing" }
      }.not_to change(Task, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(value="Pricing page"))
      expect(response.body).to include(%(value="https://example.com/pricing"))
      expect(response.body).to include(%(value="tab"))
    end

    it "uses the address as the title when the page has none" do
      get new_task_path, params: { url: "https://example.com/untitled" }

      title = Nokogiri::HTML(response.body).at_css("#task_title")
      expect(title["value"]).to eq("https://example.com/untitled")
    end

    it "sends a signed-out person to sign in first" do
      sign_out tenant.member

      get new_task_path, params: { title: "Later" }

      expect(response).to redirect_to(new_user_session_path)
    end

    it "saves the tab as a task and goes to the list" do
      post tasks_path(format: :html),
        params: { task: { title: "Pricing page", url: "https://example.com/pricing", source: "tab" } }

      task = tenant.team.tasks.find_by!(title: "Pricing page")
      expect(task.source).to eq("tab")
      expect(task.url).to eq("https://example.com/pricing")
      expect(response).to redirect_to(dashboard_path)
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

    describe "starting with a project's name" do
      let!(:project) { create(:project, team: tenant.team, name: "Acme") }

      it "files the task under that project and drops the name from the title" do
        post tasks_path, params: { task: { title: "acme: send the invoice" } }

        task = Task.find_by(title: "send the invoice")
        expect(task.project).to eq(project)
      end

      it "works for a spoken task too" do
        post tasks_path, params: { task: { title: "Acme call Sam", source: "voice" } }

        expect(Task.find_by(title: "call Sam").project).to eq(project)
      end

      it "matches a hyphenated word to a name with spaces" do
        suite = create(:project, team: tenant.team, name: "Slater Suite")
        post tasks_path, params: { task: { title: "slater-suite fix the search" } }

        expect(Task.find_by(title: "fix the search").project).to eq(suite)
      end

      it "matches a name spoken as separate words" do
        suite = create(:project, team: tenant.team, name: "slater-suite")
        post tasks_path, params: { task: { title: "Slater Suite fix the search", source: "voice" } }

        expect(Task.find_by(title: "fix the search").project).to eq(suite)
      end

      it "prefers the longest name that fits" do
        create(:project, team: tenant.team, name: "Slater")
        suite = create(:project, team: tenant.team, name: "Slater Suite")
        post tasks_path, params: { task: { title: "slater suite, ship it" } }

        expect(Task.find_by(title: "ship it").project).to eq(suite)
      end

      it "matches any of a project's other names" do
        suite = create(:project, team: tenant.team, name: "slater-suite", aliases: [ "Slater", "Slater Sweet" ])
        post tasks_path, params: { task: { title: "Slater Sweet fix the search", source: "voice" } }
        post tasks_path, params: { task: { title: "slater: ship it" } }

        expect(Task.find_by(title: "fix the search").project).to eq(suite)
        expect(Task.find_by(title: "ship it").project).to eq(suite)
      end

      it "matches a project named after a folder" do
        app = create(:project, team: tenant.team, name: "rails_app")
        post tasks_path, params: { task: { title: "rails-app bump gems" } }

        expect(Task.find_by(title: "bump gems").project).to eq(app)
      end

      it "leaves a title that is only the project's name alone" do
        post tasks_path, params: { task: { title: "Acme" } }

        expect(Task.find_by(title: "Acme").project).to be_nil
      end

      it "leaves a saved tab's title alone" do
        post tasks_path, params: { task: { title: "Acme pricing page", source: "tab" } }

        expect(Task.find_by(title: "Acme pricing page").project).to be_nil
      end

      it "keeps a project chosen by hand" do
        other = create(:project, team: tenant.team, name: "Beta")
        post tasks_path, params: { task: { title: "Acme handover", project_id: other.id } }

        expect(Task.find_by(title: "Acme handover").project).to eq(other)
      end

      it "never matches another team's project" do
        create(:project, team: create_tenant.team, name: "Globex")
        post tasks_path, params: { task: { title: "Globex merger" } }

        expect(Task.find_by(title: "Globex merger").project).to be_nil
      end
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

    it "goes back to the list after saving, where the edit was started" do
      patch task_path(task), params: { task: { title: "Renamed" } }

      expect(response).to redirect_to(dashboard_path)
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

    describe "by day" do
      around { |example| travel_to(Time.utc(2026, 10, 29, 12, 0)) { example.run } }

      before do
        create(:task, :done, team: tenant.team, title: "Done this morning", completed_at: 2.hours.ago)
        create(:task, :done, team: tenant.team, title: "Done yesterday", completed_at: 1.day.ago)
        create(:task, :done, team: tenant.team, title: "Done last week", completed_at: Time.utc(2026, 10, 22, 9, 0))
      end

      it "puts each finished task under the day it was finished" do
        get tasks_path

        headings = Nokogiri::HTML(response.body).css(".day-group__head").map { |h| h.text.squish }
        expect(headings).to eq([ "Today 1", "Yesterday 1", "Thursday 22 October 1" ])
      end

      it "shows only the day you pick" do
        get tasks_path, params: { day: "2026-10-28" }

        expect(response.body).to include("Done yesterday")
        expect(response.body).not_to include("Done this morning")
        expect(response.body).not_to include("Done last week")
      end

      it "offers every day with something finished in the picker, with its count" do
        get tasks_path

        options = Nokogiri::HTML(response.body).css("select#day option").map(&:text)
        expect(options).to eq([ "Every day", "Today · 1", "Yesterday · 1", "Thursday 22 October · 1" ])
      end

      it "says so when the picked day has nothing in it" do
        get tasks_path, params: { day: "2026-10-01" }

        expect(response.body).to include("Nothing that day")
      end

      it "shows every day when the day is not a date, rather than failing" do
        get tasks_path, params: { day: "yesterday'; drop table tasks" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Done this morning", "Done last week")
      end

      it "never counts another team's work in a day" do
        create(:task, :done, team: create_tenant.team, completed_at: 1.day.ago)

        get tasks_path

        expect(Nokogiri::HTML(response.body).css("select#day option").map(&:text)).to include("Yesterday · 1")
      end
    end
  end
end
