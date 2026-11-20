# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Low priority tasks" do
  let(:tenant) { create_tenant }
  let!(:task) { create(:task, team: tenant.team, assignee: tenant.member) }

  before { sign_in tenant.member }

  describe "putting a task off" do
    it "moves it out of the list and onto the top of the low priority list" do
      post task_low_priority_path(task), as: :turbo_stream

      expect(task.reload).to be_low_priority
      expect(response.body).to include(%(action="remove" target="task_#{task.id}"))
      expect(response.body).to include(%(action="prepend" target="low_priorities"))
    end

    it "shows it in the low priority section, after the rest, on the next visit" do
      other = create(:task, team: tenant.team, assignee: tenant.member)
      task.low_prioritize!

      get dashboard_path

      page = Nokogiri::HTML(response.body)
      expect(page.css("#low_priorities .checklist__title").map(&:text)).to eq([ task.title ])
      expect(page.css("#tasks .checklist__title").map(&:text)).to eq([ other.title ])
      sections = page.css(".today__section").map { |section| section["aria-label"] || section.at_css("h2")&.text&.strip }
      expect(sections.index("Low priority")).to eq(sections.index("To do") + 1)
    end

    # A priority is one list and low priority another. Putting a priority off
    # takes it out of the priority list rather than leaving it in both.
    it "takes a priority task out of the priority list" do
      task.prioritize!

      post task_low_priority_path(task), as: :turbo_stream

      expect(task.reload).to be_low_priority
      expect(task).not_to be_priority
    end

    it "is safe to send twice — it stays on top" do
      post task_low_priority_path(task), as: :turbo_stream
      position = task.reload.position

      post task_low_priority_path(task), as: :turbo_stream

      expect(task.reload.position).to eq(position)
    end

    it "leaves a finished task alone" do
      task.complete!

      post task_low_priority_path(task), as: :turbo_stream

      expect(task.reload).not_to be_low_priority
      expect(response.body).not_to include(%(action="prepend"))
    end

    it "works without JavaScript" do
      post task_low_priority_path(task)

      expect(response).to redirect_to(dashboard_path)
      expect(task.reload).to be_low_priority
    end
  end

  describe "bringing it back" do
    before { task.low_prioritize! }

    it "puts it back on top of the rest" do
      delete task_low_priority_path(task), as: :turbo_stream

      expect(task.reload).not_to be_low_priority
      expect(response.body).to include(%(action="prepend" target="tasks"))
    end

    it "lifts it straight into the priority list when starred" do
      post task_priority_path(task), as: :turbo_stream

      expect(task.reload).to be_priority
      expect(task).not_to be_low_priority
      expect(response.body).to include(%(action="prepend" target="priorities"))
    end
  end

  it "puts a reopened low priority task back in the low priority list" do
    task.low_prioritize!
    task.complete!

    delete task_completion_path(task), as: :turbo_stream

    expect(response.body).to include(%(action="prepend" target="low_priorities"))
  end

  it "returns 404 for another team's task, rather than 403" do
    theirs = create(:task, team: create_tenant.team)

    post task_low_priority_path(theirs)

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload).not_to be_low_priority
  end
end
