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

    it "keeps ids separate per team" do
      other = create_tenant
      theirs = create(:task, team: other.team, source: "claude", external_id: "shared-id", title: "Theirs")

      push({ title: "Mine", source: "claude", external_id: "shared-id" })

      expect(theirs.reload.title).to eq("Theirs")
      expect(tenant.team.tasks.find_by(external_id: "shared-id").title).to eq("Mine")
    end
  end
end
