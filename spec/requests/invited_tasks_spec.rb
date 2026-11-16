# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tasks for somebody invited who has not joined yet" do
  let(:tenant) { create_tenant }
  let(:invitation) { create(:team_invitation, team: tenant.team, email: "sam@example.com") }

  describe "assigning from the task form" do
    let(:task) { create(:task, team: tenant.team, assignee: tenant.owner) }

    it "lets an admin put a task on an invitation, off anybody's list" do
      sign_in tenant.owner

      patch task_path(task), params: { task: { owner: "invitation_#{invitation.id}" } }

      expect(task.reload).to have_attributes(assignee: nil, invitation: invitation)
      expect(response).to redirect_to(people_path)
    end

    it "moves it back to a person, and off the invitation" do
      task.update!(assignee: nil, invitation: invitation)
      sign_in tenant.owner

      patch task_path(task), params: { task: { owner: tenant.member.id.to_s } }

      expect(task.reload).to have_attributes(assignee: tenant.member, invitation: nil)
    end

    it "offers the invitation in the picker to an admin only" do
      invitation
      sign_in tenant.owner
      get edit_task_path(task)
      expect(response.body).to include("sam@example.com (invited)")

      sign_in tenant.member
      get edit_task_path(task)
      expect(response.body).not_to include("sam@example.com")
    end

    # A member cannot see invitations, so one does not exist for them.
    it "404s for a member" do
      sign_in tenant.member

      patch task_path(task), params: { task: { owner: "invitation_#{invitation.id}" } }

      expect(response).to have_http_status(:not_found)
      expect(task.reload.invitation).to be_nil
    end

    it "404s for another team's invitation" do
      elsewhere = create(:team_invitation, team: create_tenant.team)
      sign_in tenant.owner

      patch task_path(task), params: { task: { owner: "invitation_#{elsewhere.id}" } }

      expect(response).to have_http_status(:not_found)
    end

    it "404s for an invitation already accepted" do
      accepted = create(:team_invitation, :accepted, team: tenant.team)
      sign_in tenant.owner

      patch task_path(task), params: { task: { owner: "invitation_#{accepted.id}" } }

      expect(response).to have_http_status(:not_found)
    end

    it "adds a new task straight onto the invitation" do
      sign_in tenant.owner

      get new_task_path(owner: "invitation_#{invitation.id}")
      expect(response.body).to include(%(selected="selected" value="invitation_#{invitation.id}"))

      post tasks_path, params: { task: { title: "Read the handbook", source: "typed", owner: "invitation_#{invitation.id}" } }

      expect(tenant.team.tasks.last).to have_attributes(title: "Read the handbook", assignee: nil, invitation: invitation)
    end
  end

  describe "the team page" do
    before { create(:task, team: tenant.team, assignee: nil, invitation: invitation, title: "Read the handbook") }

    it "shows an admin the invited person's card, with what waits for them" do
      sign_in tenant.owner

      get people_path

      card = Nokogiri::HTML(response.body).at_css(".person--invited")
      expect(card.text).to include("sam@example.com", "Invited", "Read the handbook")
      expect(card.at_css(".person__counts").text.squish).to eq("1 waiting for them")
      expect(response.body).not_to include("Nobody’s yet")
    end

    it "keeps an expired invitation's card while tasks wait on it" do
      invitation.update!(expires_at: 1.day.ago)
      create(:team_invitation, :expired, team: tenant.team, email: "gone@example.com")
      sign_in tenant.owner

      get people_path

      expect(response.body).to include("Invite expired", "Read the handbook")
      expect(response.body).not_to include("gone@example.com")
    end

    it "shows a member no invitations" do
      sign_in tenant.member

      get people_path

      expect(response.body).not_to include("sam@example.com")
    end
  end

  describe "accepting the invitation" do
    it "puts what was waiting on the new person's list, in the order it was given" do
      create_list(:task, 3, team: tenant.team, assignee: nil, invitation: invitation)
      waiting = invitation.tasks.in_order.to_a
      sam = create(:user, email: "sam@example.com")
      sign_in sam

      post accept_invitation_path(invitation.token)

      expect(tenant.team.tasks.assigned_to(sam).in_order).to eq(waiting)
      expect(invitation.tasks).to be_empty
    end
  end

  describe "revoking the invitation" do
    it "leaves its tasks with nobody" do
      task = create(:task, team: tenant.team, assignee: nil, invitation: invitation)
      sign_in tenant.owner

      delete team_invitation_path(tenant.team, invitation)

      expect(task.reload).to have_attributes(assignee: nil, invitation: nil)
    end
  end

  describe "assigning through the inbox" do
    def push(params, as:)
      token = as.membership_for(tenant.team).inbox_token
      post inbox_tasks_path, params: params, headers: { "Authorization" => "Bearer #{token}" }, as: :json
    end

    before { invitation }

    it "lets an admin's token name the invited person by email" do
      push({ title: "Read the handbook", assignee: "Sam@Example.com" }, as: tenant.owner)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("assignee" => "sam@example.com", "invited" => true)
      expect(tenant.team.tasks.last).to have_attributes(assignee: nil, invitation: invitation)
    end

    it "finds them by the part of the email before the @" do
      push({ title: "Read the handbook", assignee: "sam" }, as: tenant.owner)

      expect(tenant.team.tasks.last.invitation).to eq(invitation)
    end

    it "prefers somebody already on the team with that name" do
      tenant.member.update!(first_name: "Sam", last_name: "Lee")

      push({ title: "Fix the navbar", assignee: "sam" }, as: tenant.owner)

      expect(tenant.team.tasks.last).to have_attributes(assignee: tenant.member, invitation: nil)
    end

    it "lists the invited in the refusal for an admin" do
      push({ title: "Lost", assignee: "Zebedee" }, as: tenant.owner)

      expect(response.parsed_body["errors"].first).to include("sam@example.com (invited)")
    end

    it "does not let a member's token find or learn of the invitation" do
      push({ title: "Read the handbook", assignee: "sam@example.com" }, as: tenant.member)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].first).not_to include("sam@example.com (invited)")
      expect(Task.count).to eq(0)
    end

    it "never finds another team's invitation" do
      create(:team_invitation, team: create_tenant.team, email: "pat@example.com")

      push({ title: "Lost", assignee: "pat@example.com" }, as: tenant.owner)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe Task do
    it "refuses an invitation to another team" do
      task = build(:task, team: tenant.team, assignee: nil, invitation: create(:team_invitation))

      expect(task).not_to be_valid
      expect(task.errors[:invitation]).to be_present
    end

    it "drops the invitation when it is given to a person" do
      task = create(:task, team: tenant.team, assignee: nil, invitation: invitation)

      task.update!(assignee: tenant.member)

      expect(task.invitation).to be_nil
    end
  end
end
