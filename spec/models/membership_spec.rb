# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: memberships
#
#  id                 :bigint           not null, primary key
#  hidden_project_ids :bigint           default([]), not null, is an Array
#  inbox_token        :string           not null
#  role               :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  team_id            :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_memberships_on_inbox_token          (inbox_token) UNIQUE
#  index_memberships_on_team_id              (team_id)
#  index_memberships_on_team_id_and_role     (team_id,role)
#  index_memberships_on_user_id              (user_id)
#  index_memberships_on_user_id_and_team_id  (user_id,team_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe Membership do
  describe "roles" do
    it "orders roles so that comparisons work" do
      expect(described_class.roles).to eq("member" => 0, "admin" => 1, "owner" => 2)
    end

    it "answers at_least? by rank rather than by name" do
      owner  = build(:membership, role: :owner)
      admin  = build(:membership, role: :admin)
      member = build(:membership, role: :member)

      expect(owner).to be_at_least(:admin)
      expect(admin).to be_at_least(:admin)
      expect(member).not_to be_at_least(:admin)
      expect(member).to be_at_least(:member)
    end
  end

  describe "uniqueness" do
    it "allows a user only one membership per team" do
      team = create(:team)
      user = create(:user)
      create(:membership, user: user, team: team)

      duplicate = build(:membership, user: user, team: team)
      expect(duplicate).not_to be_valid
    end

    it "allows the same user in different teams" do
      user = create(:user)
      create(:membership, user: user, team: create(:team))
      expect(build(:membership, user: user, team: create(:team))).to be_valid
    end
  end

  describe "the last-owner invariant" do
    let(:team) { create(:team) }
    let!(:owner) { create(:membership, :owner, team: team) }

    it "refuses to demote the only owner" do
      owner.role = :member
      expect(owner).not_to be_valid
      expect(owner.errors[:role].first).to include('at least one owner')
    end

    it "refuses to destroy the only owner" do
      expect(owner.destroy).to be(false)
      expect(team.reload.memberships).to include(owner)
    end

    it "allows demoting an owner when another owner remains" do
      create(:membership, :owner, team: team)
      owner.role = :member
      expect(owner).to be_valid
    end

    it "allows destroying an owner when another owner remains" do
      create(:membership, :owner, team: team)
      expect(owner.destroy).to be_truthy
    end

    it "allows a non-owner to be destroyed freely" do
      member = create(:membership, :member, team: team)
      expect(member.destroy).to be_truthy
    end

    it "reports #last_owner? correctly" do
      expect(owner).to be_last_owner
      create(:membership, :owner, team: team)
      expect(owner.reload).not_to be_last_owner
    end
  end

  describe "seat syncing" do
    it "enqueues a seat sync when a member joins" do
      team = create(:team)
      expect { create(:membership, team: team) }
        .to have_enqueued_job(Billing::SyncSeatsJob).with(team.id)
    end

    it "enqueues a seat sync when a member leaves" do
      team = create(:team)
      create(:membership, :owner, team: team)
      membership = create(:membership, team: team)

      expect { membership.destroy }
        .to have_enqueued_job(Billing::SyncSeatsJob).with(team.id)
    end
  end

  describe "finding somebody by what they are called" do
    let(:team) { create(:team) }
    let!(:sam) { create(:membership, team: team, user: create(:user, first_name: "Sam", last_name: "Lee", email: "sam@example.com")) }
    let!(:alex) { create(:membership, team: team, user: create(:user, first_name: "Alex", last_name: "Okafor")) }

    it "finds a person by first name, full name or email, ignoring case and spacing" do
      expect(team.memberships.named("sam")).to eq(sam)
      expect(team.memberships.named("  Sam   LEE ")).to eq(sam)
      expect(team.memberships.named("SAM@example.com")).to eq(sam)
    end

    it "finds nobody for a blank or unknown name" do
      expect(team.memberships.named("")).to be_nil
      expect(team.memberships.named("Zebedee")).to be_nil
    end

    it "finds nobody when a first name is shared, and still finds each by full name" do
      other_sam = create(:membership, team: team, user: create(:user, first_name: "Sam", last_name: "Okafor"))

      expect(team.memberships.named("Sam")).to be_nil
      expect(team.memberships.named("Sam Okafor")).to eq(other_sam)
    end

    it "only looks among the memberships it is asked through" do
      expect(create(:team).memberships.named("Sam")).to be_nil
    end
  end

  describe "leaving" do
    let(:team) { create(:team) }
    let(:leaver) { create(:membership, team: team) }

    before { create(:membership, :owner, team: team) }

    it "hands what the person still had to do back to the team, and keeps what they finished theirs" do
      open_task = create(:task, team: team, assignee: leaver.user)
      done_task = create(:task, :done, team: team, assignee: leaver.user)

      leaver.destroy!

      expect(open_task.reload.assignee).to be_nil
      expect(done_task.reload.assignee).to eq(leaver.user)
    end

    it "leaves their tasks on other teams alone" do
      elsewhere = create(:membership, user: leaver.user)
      theirs = create(:task, team: elsewhere.team, assignee: leaver.user)

      leaver.destroy!

      expect(theirs.reload.assignee).to eq(leaver.user)
    end
  end

  describe "the inbox token" do
    it "gives each membership its own" do
      one = create(:membership)
      two = create(:membership)

      expect(one.inbox_token).to be_present
      expect(one.inbox_token).not_to eq(two.inbox_token)
    end
  end
end
