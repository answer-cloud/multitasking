# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Task priorities" do
  let(:tenant) { create_tenant }
  let!(:task) { create(:task, team: tenant.team) }

  before { sign_in tenant.member }

  describe "making a task a priority" do
    it "moves it out of the list and onto the top of the priority list" do
      post task_priority_path(task), as: :turbo_stream

      expect(task.reload).to be_priority
      expect(response.body).to include(%(action="remove" target="task_#{task.id}"))
      expect(response.body).to include(%(action="prepend" target="priorities"))
    end

    it "shows it in the priority section, above the rest, on the next visit" do
      other = create(:task, team: tenant.team)
      task.prioritize!

      get dashboard_path

      priorities = Nokogiri::HTML(response.body).css("#priorities .checklist__title").map(&:text)
      rest = Nokogiri::HTML(response.body).css("#tasks .checklist__title").map(&:text)
      expect(priorities).to eq([ task.title ])
      expect(rest).to eq([ other.title ])
    end

    it "is safe to send twice — it stays on top" do
      post task_priority_path(task), as: :turbo_stream
      position = task.reload.position

      post task_priority_path(task), as: :turbo_stream

      expect(task.reload.position).to eq(position)
    end

    # A finished task is in neither list. Pinning it must not put it back on
    # the dashboard as if it were still to do.
    it "leaves a finished task alone" do
      task.complete!

      post task_priority_path(task), as: :turbo_stream

      expect(task.reload).not_to be_priority
      expect(response.body).not_to include(%(action="prepend"))
    end

    it "works without JavaScript" do
      post task_priority_path(task)

      expect(response).to redirect_to(dashboard_path)
      expect(task.reload).to be_priority
    end
  end

  describe "letting it back down" do
    before { task.prioritize! }

    it "puts it back on top of the rest" do
      delete task_priority_path(task), as: :turbo_stream

      expect(task.reload).not_to be_priority
      expect(response.body).to include(%(action="prepend" target="tasks"))
    end
  end

  it "puts a reopened priority back in the priority list" do
    task.prioritize!
    task.complete!

    delete task_completion_path(task), as: :turbo_stream

    expect(response.body).to include(%(action="prepend" target="priorities"))
  end

  it "returns 404 for another team's task, rather than 403" do
    theirs = create(:task, team: create_tenant.team)

    post task_priority_path(theirs)

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload).not_to be_priority
  end
end
