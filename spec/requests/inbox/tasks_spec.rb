# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inbox: tasks pushed in by other tools" do
  let(:tenant) { create_tenant }
  let(:headers) { { "Authorization" => "Bearer #{tenant.team.inbox_token}" } }

  def push(params, with: headers)
    post inbox_tasks_path, params: params, headers: with, as: :json
  end

  describe "authentication" do
    it "refuses a request with no token" do
      push({ title: "Sneaky" }, with: {})

      expect(response).to have_http_status(:unauthorized)
      expect(Task.count).to eq(0)
    end

    it "refuses a wrong token" do
      push({ title: "Sneaky" }, with: { "Authorization" => "Bearer nope" })

      expect(response).to have_http_status(:unauthorized)
    end

    # The token alone picks the team. A team_id in the body is ignored, so a
    # token for one team can never write into another.
    it "writes only to the token's team, whatever the body says" do
      other = create_tenant

      push({ title: "Smuggled", team_id: other.team.id })

      expect(Task.find_by(title: "Smuggled").team).to eq(tenant.team)
    end
  end

  describe "creating" do
    it "adds a task for the team" do
      push({ title: "Review Claude: dark mode", source: "claude", url: "https://example.com/pr/1" })

      expect(response).to have_http_status(:created)
      task = tenant.team.tasks.last
      expect(task.title).to eq("Review Claude: dark mode")
      expect(task.source).to eq("claude")
      expect(task.url).to eq("https://example.com/pr/1")
    end

    it "keeps a link back to the conversation in the agent's app" do
      push({ title: "Review Codex: tests", source: "codex", url: "codex://threads/019a2b3c" })

      expect(tenant.team.tasks.last.link).to eq("codex://threads/019a2b3c")
    end

    it "does not let a hook pretend it was typed" do
      push({ title: "Disguised", source: "typed" })

      expect(tenant.team.tasks.last.source).to eq("claude")
    end

    it "explains a task it cannot save" do
      push({ title: "" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("Title can't be blank")
    end
  end

  describe "filing by folder" do
    it "makes a project for a repository the first time an agent works there" do
      push({ title: "Review Claude: tests", source: "claude", directory: "/Users/you/code/storefront" })

      task = tenant.team.tasks.last
      expect(task.project.name).to eq("storefront")
      expect(task.project.directory).to eq("/Users/you/code/storefront")
    end

    it "files later tasks from the same folder under the same project" do
      project = create(:project, team: tenant.team, directory: "/code/storefront")

      push({ title: "One", source: "claude", directory: "/code/storefront" })
      push({ title: "Two", source: "codex", directory: "/code/storefront/" })

      expect(tenant.team.tasks.map(&:project)).to all(eq(project))
      expect(tenant.team.projects.count).to eq(1)
    end

    it "leaves a task where somebody filed it by hand" do
      chosen = create(:project, team: tenant.team, name: "Chosen")
      task = create(:task, team: tenant.team, source: "claude", external_id: "session-1", project: chosen)

      push({ title: "Again", source: "claude", external_id: "session-1", directory: "/code/storefront" })

      expect(task.reload.project).to eq(chosen)
    end

    it "files nothing when no folder is sent" do
      push({ title: "From nowhere", source: "slack" })

      expect(tenant.team.tasks.last.project).to be_nil
      expect(tenant.team.projects.count).to eq(0)
    end

    # The token picks the team, and the project comes from that team only.
    it "never files a task under another team's project for the same folder" do
      theirs = create(:project, directory: "/code/storefront")

      push({ title: "Mine", source: "claude", directory: "/code/storefront" })

      expect(tenant.team.tasks.last.project).not_to eq(theirs)
      expect(tenant.team.tasks.last.project.team).to eq(tenant.team)
    end
  end

  describe "pinging the same thing again" do
    it "updates one task rather than adding a second" do
      push({ title: "Review Claude: first", source: "claude", external_id: "session-1" })
      push({ title: "Claude needs you: first", source: "claude", external_id: "session-1" })

      expect(response).to have_http_status(:ok)
      expect(tenant.team.tasks.count).to eq(1)
      expect(tenant.team.tasks.first.title).to eq("Claude needs you: first")
    end

    it "reopens a task that was already ticked off, and marks it fresh" do
      task = create(:task, :done, :quiet, team: tenant.team, source: "codex", external_id: "thread-9")

      push({ title: "Review Codex: again", source: "codex", external_id: "thread-9" })

      task.reload
      expect(task).not_to be_done
      expect(task).not_to be_quiet
    end

    # The dashboard's stream prepends it, so a reload must agree.
    it "moves the task back to the top of the list, above anything dragged there" do
      task = create(:task, team: tenant.team, source: "claude", external_id: "session-2")
      dragged = create(:task, team: tenant.team)
      dragged.move_to(0)

      push({ title: "Claude needs you: again", source: "claude", external_id: "session-2" })

      expect(tenant.team.tasks.pending.in_order.first).to eq(task)
    end

    it "keeps a long title whole" do
      title = "Review Claude: #{"word " * 150}".strip

      push({ title: title, source: "claude", external_id: "session-3" })

      expect(tenant.team.tasks.find_by(external_id: "session-3").title).to eq(title)
    end

    it "keeps ids separate per team" do
      other = create_tenant
      theirs = create(:task, team: other.team, source: "claude", external_id: "shared-id", title: "Theirs")

      push({ title: "Mine", source: "claude", external_id: "shared-id" })

      expect(theirs.reload.title).to eq("Theirs")
      expect(tenant.team.tasks.find_by(external_id: "shared-id").title).to eq("Mine")
    end
  end

  describe "a task handed to an agent from its row" do
    let!(:task) { create(:task, team: tenant.team, title: "Fix the login bug", handed_to: "claude", handed_at: 5.minutes.ago) }

    it "is taken over by the session it started, rather than joined by a second task" do
      push({ title: "Review Claude: Fix the login bug Only on Safari.", source: "claude", external_id: "session-1",
             prompt: "Fix the login bug Only on Safari." })

      expect(tenant.team.tasks.count).to eq(1)
      expect(task.reload.external_id).to eq("session-1")
      expect(task.title).to eq("Review Claude: Fix the login bug Only on Safari.")
      expect(task.source).to eq("claude")
    end

    it "keeps the same task on the session's next ping" do
      2.times { push({ title: "Review Claude: Fix the login bug", source: "claude", external_id: "session-1", prompt: "Fix the login bug" }) }

      expect(tenant.team.tasks.count).to eq(1)
    end

    it "is not taken over by the other agent" do
      push({ title: "Review Codex: Fix the login bug", source: "codex", external_id: "thread-1", prompt: "Fix the login bug" })

      expect(tenant.team.tasks.count).to eq(2)
      expect(task.reload.external_id).to be_nil
    end

    it "is not taken over by a session that was asked something else" do
      push({ title: "Review Claude: Add dark mode", source: "claude", external_id: "session-2", prompt: "Add dark mode" })

      expect(tenant.team.tasks.count).to eq(2)
      expect(task.reload.external_id).to be_nil
    end

    it "is never matched to another team's handed-off task" do
      theirs = create(:task, team: create_tenant.team, title: "Fix the login bug", handed_to: "claude", handed_at: 1.minute.ago)

      push({ title: "Review Claude: Fix the login bug", source: "claude", external_id: "session-1", prompt: "Fix the login bug" })

      expect(theirs.reload.external_id).to be_nil
      expect(task.reload.external_id).to eq("session-1")
    end
  end
end
