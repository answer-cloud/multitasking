# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: tasks
#
#  id               :bigint           not null, primary key
#  completed_at     :datetime
#  handed_at        :datetime
#  handed_to        :string
#  last_activity_at :datetime         not null
#  notes            :text
#  position         :integer          default(0), not null
#  priority         :boolean          default(FALSE), not null
#  source           :string           default("typed"), not null
#  title            :string           not null
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  created_by_id    :bigint
#  external_id      :string
#  project_id       :bigint
#  team_id          :bigint           not null
#
# Indexes
#
#  index_tasks_on_created_by_id                       (created_by_id)
#  index_tasks_on_project_id                          (project_id)
#  index_tasks_on_team_id                             (team_id)
#  index_tasks_on_team_id_and_completed_at            (team_id,completed_at)
#  index_tasks_on_team_id_and_source_and_external_id  (team_id,source,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (project_id => projects.id) ON DELETE => nullify
#  fk_rails_...  (team_id => teams.id)
#
RSpec.describe Task do
  describe "validations" do
    # Controllers look the project up through the team; this is the backstop.
    it "refuses a project from another team" do
      task = build(:task)
      task.project = create(:project)

      expect(task).not_to be_valid
      expect(task.errors[:project]).to include("must belong to this team")
    end

    it "needs a title" do
      expect(build(:task, title: "")).not_to be_valid
    end

    it "accepts only known sources" do
      expect(build(:task, source: "carrier-pigeon")).not_to be_valid
    end

    # A url is rendered as a link, so anything other than http(s) — a
    # javascript: url above all — must never be saved.
    it "accepts only http and https links" do
      expect(build(:task, url: "https://example.com")).to be_valid
      expect(build(:task, url: "javascript:alert(1)")).not_to be_valid
    end

    # The one exception: a link back to the conversation in the Claude or
    # Codex app, in exactly the shape each app opens.
    it "accepts links back to a Claude session or a Codex thread, and no other app link" do
      expect(build(:task, url: "claude://code/continue?session=local_cc0dd8fb-2cc7")).to be_valid
      expect(build(:task, url: "codex://threads/019a2b3c-4d5e")).to be_valid

      expect(build(:task, url: "claude://code/new?q=rm+-rf")).not_to be_valid
      expect(build(:task, url: "codex://threads/abc?prompt=hi")).not_to be_valid
      expect(build(:task, url: "slack://open")).not_to be_valid
    end
  end

  describe "link" do
    it "names the app an app link opens" do
      task = build(:task, url: "codex://threads/019a2b3c")

      expect(task.link).to eq("codex://threads/019a2b3c")
      expect(task.app_name).to eq("Codex")
    end

    it "is nil for a url written around the validation" do
      task = create(:task)
      task.update_column(:url, "claude://code/new?q=oops")

      expect(task.link).to be_nil
    end
  end

  describe "quiet" do
    it "is quiet once nobody has touched it for a while" do
      expect(build(:task, last_activity_at: 3.days.ago)).to be_quiet
      expect(build(:task, last_activity_at: 1.hour.ago)).not_to be_quiet
    end

    it "is never quiet once it is done" do
      expect(build(:task, :done, last_activity_at: 1.month.ago)).not_to be_quiet
    end
  end

  describe "finishing and reopening" do
    let(:task) { create(:task, :quiet) }

    it "records when it was finished" do
      task.complete!

      expect(task.completed_at).to be_within(1.second).of(Time.current)
    end

    it "comes back fresh when reopened" do
      task.complete!
      task.reopen!

      expect(task).not_to be_done
      expect(task).not_to be_quiet
    end
  end

  describe "the order of the list" do
    let(:team) { create(:team) }
    let!(:first) { create(:task, team: team) }
    let!(:second) { create(:task, team: team) }
    let!(:third) { create(:task, team: team) }

    def listed = team.tasks.pending.in_order.to_a

    it "puts a new task on top" do
      expect(listed).to eq([ third, second, first ])
    end

    it "moves a task to the place it was dropped and keeps the rest in order" do
      third.move_to(2)

      expect(listed).to eq([ second, first, third ])
    end

    it "lands in the same place when the same move is sent twice" do
      first.move_to(0)
      first.move_to(0)

      expect(listed).to eq([ first, third, second ])
    end

    it "keeps a move past either end inside the list" do
      second.move_to(99)

      expect(listed.last).to eq(second)
    end

    it "puts a reopened task back on top" do
      first.complete!
      first.reopen!

      expect(listed.first).to eq(first)
    end
  end

  describe "priority" do
    let(:team) { create(:team) }
    let!(:first) { create(:task, team: team) }
    let!(:second) { create(:task, team: team) }
    let!(:third) { create(:task, team: team) }

    def priorities = team.tasks.pending.prioritized.in_order.to_a
    def rest = team.tasks.pending.unprioritized.in_order.to_a

    it "moves a task out of the rest and onto the top of the priority list" do
      first.prioritize!
      second.prioritize!

      expect(priorities).to eq([ second, first ])
      expect(rest).to eq([ third ])
    end

    it "puts a task let back down on top of the rest" do
      first.prioritize!
      first.deprioritize!

      expect(rest.first).to eq(first)
    end

    # The two lists are numbered apart, so a drag in one never moves the other.
    it "drags within the priority list without touching the rest" do
      first.prioritize!
      second.prioritize!

      expect { first.move_to(0) }.not_to(change { rest })
      expect(priorities).to eq([ first, second ])
    end

    it "is not activity, so a quiet task stays quiet" do
      first.update!(last_activity_at: 3.days.ago)

      first.prioritize!

      expect(first.reload).to be_quiet
    end

    it "comes back a priority when a finished one is reopened" do
      first.prioritize!
      first.complete!
      first.reopen!

      expect(priorities).to eq([ first ])
    end
  end

  describe "handing to an agent" do
    let(:team) { create(:team) }
    let(:project) { create(:project, team: team, directory: "/code/storefront") }
    let(:task) { create(:task, team: team, project: project, title: "Fix the login bug", notes: "Only on Safari.") }

    def query(link) = Rack::Utils.parse_query(URI.parse(link).query)

    it "opens a new Claude session with the task typed in, in the project's folder" do
      link = task.agent_link("claude")

      expect(link).to start_with("claude://code/new?")
      expect(query(link)).to eq("q" => "Fix the login bug\n\nOnly on Safari.", "folder" => "/code/storefront")
    end

    # Codex reads different names for the same two things.
    it "opens a new Codex thread with the task typed in, in the project's folder" do
      link = task.agent_link("codex")

      expect(link).to start_with("codex://threads/new?")
      expect(query(link)).to eq("prompt" => "Fix the login bug\n\nOnly on Safari.", "path" => "/code/storefront")
    end

    it "leaves the folder to the app when the project has none" do
      task.update!(project: nil, notes: nil)

      expect(query(task.agent_link("claude"))).to eq("q" => "Fix the login bug")
    end

    it "records who has it until the agent reports back" do
      task.hand_to!("codex")

      expect(task).to be_with_agent
      expect(task.handed_to_name).to eq("Codex")

      task.update!(external_id: "thread-1")

      expect(task).not_to be_with_agent
    end

    it "accepts only the agents it knows" do
      expect(build(:task, handed_to: "gemini")).not_to be_valid
    end
  end
end
