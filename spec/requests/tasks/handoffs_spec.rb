# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Handing a task to an agent" do
  let(:tenant) { create_tenant }
  let(:project) { create(:project, team: tenant.team, directory: "/code/storefront") }
  let!(:task) { create(:task, team: tenant.team, project: project, title: "Fix the login bug") }

  before { sign_in tenant.member }

  it "sends the browser to a new Claude session on the task" do
    post task_handoff_path(task), params: { agent: "claude" }

    expect(response).to have_http_status(:see_other)
    expect(response.location).to eq("claude://code/new?folder=%2Fcode%2Fstorefront&q=Fix+the+login+bug")
  end

  it "sends the browser to a new Codex thread on the task" do
    post task_handoff_path(task), params: { agent: "codex" }

    expect(response.location).to eq("codex://threads/new?path=%2Fcode%2Fstorefront&prompt=Fix+the+login+bug")
  end

  it "notes who has it, and shows it in the row" do
    post task_handoff_path(task), params: { agent: "claude" }

    expect(task.reload.handed_to).to eq("claude")
    get dashboard_path
    expect(Nokogiri::HTML(response.body).at_css("##{ActionView::RecordIdentifier.dom_id(task)} .source").text).to eq("With Claude")
  end

  it "offers both agents on a task, and neither on one that is already an agent's conversation" do
    create(:task, team: tenant.team, title: "Review Claude: tests", source: "claude", url: "claude://code/continue?session=local_abc")

    get dashboard_path

    rows = Nokogiri::HTML(response.body).css(".checklist__item")
    buttons = rows.to_h { |row| [ row.at_css(".checklist__title").text, row.css("button.btn").map(&:text) ] }
    expect(buttons["Fix the login bug"]).to eq([ "Complete on Claude ↗", "Complete on Codex ↗" ])
    expect(buttons["Review Claude: tests"]).to be_empty
  end

  # The redirect leaves this app for a custom scheme, so only the two links the
  # model builds may come out of it — never one named in the request.
  it "refuses an agent it does not know" do
    post task_handoff_path(task), params: { agent: "https://evil.example" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(task.reload.handed_to).to be_nil
  end

  it "returns 404 for another team's task, rather than 403" do
    theirs = create(:task, team: create_tenant.team)

    post task_handoff_path(theirs), params: { agent: "claude" }

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.handed_to).to be_nil
  end
end
