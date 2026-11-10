# frozen_string_literal: true

require "rails_helper"

# Policies are tested per role, for both the permitted and the forbidden case.
# A policy spec that only asserts the happy path proves nothing.
RSpec.describe "Policies" do
  let(:team) { create(:team) }
  let(:owner)  { create(:user).tap { |u| create(:membership, :owner,  user: u, team: team) } }
  let(:admin)  { create(:user).tap { |u| create(:membership, :admin,  user: u, team: team) } }
  let(:member) { create(:user).tap { |u| create(:membership, :member, user: u, team: team) } }
  let(:outsider) { create(:user) }

  # Evaluates a policy question with Current set the way a request would set it.
  def as(user, record, question, policy_class: nil)
    acting_as(user, team: team) do
      klass = policy_class || Pundit::PolicyFinder.new(record).policy
      klass.new(user, record).public_send(question)
    end
  end

  describe TeamPolicy do
    it "lets any signed-in user create a team" do
      expect(as(member, Team, :create?)).to be(true)
    end

    it "restricts team settings to admins and above" do
      expect(as(owner,  team, :update?)).to be(true)
      expect(as(admin,  team, :update?)).to be(true)
      expect(as(member, team, :update?)).to be(false)
    end

    it "restricts deleting a team to owners" do
      expect(as(owner,  team, :destroy?)).to be(true)
      expect(as(admin,  team, :destroy?)).to be(false)
      expect(as(member, team, :destroy?)).to be(false)
    end

    it "refuses to delete a team while impersonating, even as an owner" do
      acting_as(owner, team: team) do
        Current.true_user = create(:user, :admin)
        expect(described_class.new(owner, team).destroy?).to be(false)
      end
    end

    it "lets a member leave but not the last owner" do
      expect(as(member, team, :leave?)).to be(true)
      expect(as(owner,  team, :leave?)).to be(false)
    end

    it "refuses everything to a non-member" do
      expect(as(outsider, team, :show?)).to be(false)
      expect(as(outsider, team, :update?)).to be(false)
    end
  end

  describe MembershipPolicy do
    let(:member_membership) { member.memberships.first }
    let(:owner_membership)  { owner.memberships.first }

    it "lets an admin change a member's role" do
      expect(as(admin, member_membership, :update?)).to be(true)
    end

    it "does not let an admin change an owner's role" do
      other_owner = create(:membership, :owner, team: team) # not the last owner
      expect(as(admin, other_owner, :update?)).to be(false)
    end

    it "lets an owner change another owner's role" do
      other_owner = create(:membership, :owner, team: team)
      expect(as(owner, other_owner, :update?)).to be(true)
    end

    it "never allows changing the last owner's role" do
      expect(as(owner, owner_membership, :update?)).to be(false)
    end

    it "does not let anyone change their own role" do
      expect(as(admin, admin.memberships.first, :update?)).to be(false)
    end

    it "does not let a member change roles at all" do
      expect(as(member, member_membership, :update?)).to be(false)
    end

    it "offers owner as an assignable role only to owners" do
      acting_as(owner, team: team) do
        expect(described_class.new(owner, member_membership).assignable_roles).to include("owner")
      end
      acting_as(admin, team: team) do
        expect(described_class.new(admin, member_membership).assignable_roles).not_to include("owner")
      end
    end
  end

  describe SubscriptionPolicy do
    let(:subscription) { create(:subscription, team: team) }

    it "lets admins and owners view billing, but not members" do
      expect(as(owner,  subscription, :show?)).to be(true)
      expect(as(admin,  subscription, :show?)).to be(true)
      expect(as(member, subscription, :show?)).to be(false)
    end

    it "restricts starting and managing a subscription to owners" do
      expect(as(owner,  subscription, :checkout?)).to be(true)
      expect(as(admin,  subscription, :checkout?)).to be(false)
      expect(as(member, subscription, :portal?)).to be(false)
    end

    it "blocks all money movement while impersonating, even for an owner" do
      acting_as(owner, team: team) do
        Current.true_user = create(:user, :admin)

        policy = described_class.new(owner, subscription)
        expect(policy.checkout?).to be(false)
        expect(policy.portal?).to be(false)
        expect(policy.show?).to be(true) # looking is fine; spending is not
      end
    end
  end


  describe TaskPolicy do
    let(:task) { create(:task, team: team) }

    it "lets any member add, edit, tick off and delete" do
      %i[create? update? complete? destroy?].each do |question|
        expect(as(member, task, question)).to be(true)
      end
    end

    it "refuses everything to a non-member" do
      %i[show? create? update? complete? destroy?].each do |question|
        expect(as(outsider, task, question)).to be(false)
      end
    end
  end

  describe DailySummaryPolicy do
    let(:summary) { create(:daily_summary, team: team) }

    it "lets every role read the day's summary" do
      [ owner, admin, member ].each do |user|
        expect(as(user, summary, :show?)).to be(true)
        expect(as(user, summary, :index?)).to be(true)
      end
    end

    # Only Summaries::SummarizeDay writes one. Not even an owner may write,
    # rewrite or delete what Claude said about a day.
    it "lets no role write, change or delete one" do
      [ owner, admin, member ].each do |user|
        %i[create? update? destroy?].each do |question|
          expect(as(user, summary, question)).to be(false)
        end
      end
    end

    it "refuses everything to a non-member" do
      %i[show? index?].each do |question|
        expect(as(outsider, summary, question)).to be(false)
      end
    end

    it "scopes to nothing for a non-member" do
      summary
      acting_as(outsider, team: team) do
        expect(DailySummaryPolicy::Scope.new(outsider, team.daily_summaries).resolve).to be_empty
      end
    end
  end

  describe ProjectPolicy do
    let(:project) { create(:project, team: team) }

    it "lets any member make, rename, hide and delete a project" do
      %i[show? create? update? destroy? hide?].each do |question|
        expect(as(member, project, question)).to be(true)
      end
    end

    it "refuses everything to a non-member" do
      %i[show? create? update? destroy? hide?].each do |question|
        expect(as(outsider, project, question)).to be(false)
      end
    end
  end

  describe Admin::UserPolicy do
    let(:platform_admin) { create(:user, :admin) }

    it "is closed to ordinary users" do
      expect(described_class.new(member, outsider).index?).to be(false)
    end

    it "is open to platform admins" do
      expect(described_class.new(platform_admin, outsider).index?).to be(true)
    end

    it "refuses to impersonate another admin" do
      other_admin = create(:user, :admin)
      expect(described_class.new(platform_admin, other_admin).impersonate?).to be(false)
    end

    it "refuses to impersonate yourself" do
      expect(described_class.new(platform_admin, platform_admin).impersonate?).to be(false)
    end

    it "allows impersonating an ordinary user" do
      expect(described_class.new(platform_admin, member).impersonate?).to be(true)
    end

    it "does not let a non-admin impersonate anyone" do
      expect(described_class.new(member, outsider).impersonate?).to be(false)
    end
  end

  describe SlackConnectionPolicy do
    let(:connection_of) { ->(user) { build(:slack_connection, team: team, user: user) } }

    it "lets every role link their own Slack" do
      expect(as(owner,  connection_of.(owner),  :create?)).to be(true)
      expect(as(admin,  connection_of.(admin),  :create?)).to be(true)
      expect(as(member, connection_of.(member), :create?)).to be(true)
    end

    it "lets every role unlink their own, and nobody unlink anyone else's" do
      expect(as(member, connection_of.(member), :destroy?)).to be(true)
      expect(as(owner,  connection_of.(owner),  :destroy?)).to be(true)
      expect(as(owner,  connection_of.(member), :destroy?)).to be(false)
      expect(as(admin,  connection_of.(member), :destroy?)).to be(false)
    end

    it "refuses everything to a non-member and while impersonating" do
      expect(as(outsider, connection_of.(outsider), :create?)).to be(false)

      acting_as(member, team: team) do
        Current.true_user = create(:user, :admin)
        expect(described_class.new(member, connection_of.(member)).create?).to be(false)
        expect(described_class.new(member, connection_of.(member)).destroy?).to be(false)
      end
    end
  end
end
