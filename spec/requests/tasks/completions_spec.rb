# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Task completions" do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { create_tenant }
  let!(:task) { create(:task, team: tenant.team) }

  before { sign_in tenant.member }

  describe "ticking off" do
    it "marks the task done and moves it into the jar" do
      post task_completion_path(task), as: :turbo_stream

      expect(task.reload).to be_done
      expect(response.body).to include(%(action="remove" target="task_#{task.id}"))
      expect(response.body).to include(%(action="prepend" target="done_today"))
    end

    it "is safe to send twice — the first finish time stands" do
      post task_completion_path(task), as: :turbo_stream
      first = task.reload.completed_at

      travel 1.minute do
        post task_completion_path(task), as: :turbo_stream
      end

      expect(task.reload.completed_at).to eq(first)
    end

    it "works without JavaScript" do
      post task_completion_path(task)

      expect(response).to redirect_to(dashboard_path)
      expect(task.reload).to be_done
    end
  end

  describe "unticking" do
    before { task.complete! }

    it "puts the task back on the list" do
      delete task_completion_path(task), as: :turbo_stream

      expect(task.reload).not_to be_done
      expect(response.body).to include(%(action="prepend" target="tasks"))
    end
  end

  it "returns 404 for another team's task, rather than 403" do
    theirs = create(:task, team: create_tenant.team)

    post task_completion_path(theirs)

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload).not_to be_done
  end
end
