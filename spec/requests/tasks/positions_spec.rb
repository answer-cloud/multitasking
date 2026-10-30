# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dragging a task up or down the list" do
  let(:tenant) { create_tenant }
  let!(:bottom) { create(:task, :quiet, team: tenant.team) }
  let!(:top) { create(:task, team: tenant.team) }

  before { sign_in tenant.member }

  it "saves the place it was dropped" do
    patch task_position_path(bottom), params: { position: 0 }, as: :json

    expect(response).to have_http_status(:no_content)
    expect(tenant.team.tasks.pending.in_order).to eq([ bottom, top ])
  end

  it "shows the list in that order on the next visit" do
    patch task_position_path(bottom), params: { position: 0 }, as: :json

    get dashboard_path

    expect(response.body.index(bottom.title)).to be < response.body.index(top.title)
  end

  # Rearranging the list is not working on the task.
  it "does not count as activity, so a quiet task stays quiet" do
    patch task_position_path(bottom), params: { position: 0 }, as: :json

    expect(bottom.reload).to be_quiet
  end

  it "returns 404 for another team's task and leaves it alone" do
    theirs = create(:task)

    expect {
      patch task_position_path(theirs), params: { position: 5 }, as: :json
    }.not_to(change { theirs.reload.position })

    expect(response).to have_http_status(:not_found)
  end
end
