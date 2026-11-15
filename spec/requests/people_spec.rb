# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The team page and each person's list" do
  let(:tenant) { create_tenant }
  let(:owner_membership) { tenant.owner.membership_for(tenant.team) }
  let(:member_membership) { tenant.member.membership_for(tenant.team) }

  describe "the team page" do
    it "requires authentication" do
      get people_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows everybody on the team with what each has on" do
      create(:task, team: tenant.team, assignee: tenant.member, title: "Draw the new logo")
      create(:task, :done, team: tenant.team, assignee: tenant.member)
      sign_in tenant.owner

      get people_path

      card = Nokogiri::HTML(response.body).css(".person").find { |person| person.text.include?(tenant.member.name) }
      expect(card.text).to include("Draw the new logo")
      expect(card.at_css(".person__counts").text.squish).to eq("1 to do · 1 done today")
      expect(card.at_css("a.btn")["href"]).to eq(person_path(member_membership))
    end

    it "sends your own card to your dashboard" do
      sign_in tenant.owner

      get people_path

      card = Nokogiri::HTML(response.body).css(".person").find { |person| person.text.include?(tenant.owner.name) }
      expect(card.at_css("a.btn")["href"]).to eq(dashboard_path)
    end

    it "never shows another team's people or their tasks" do
      other = create_tenant
      create(:task, team: other.team, assignee: other.member, title: "Their secret plan")
      sign_in tenant.owner

      get people_path

      expect(response.body).not_to include("Their secret plan")
      expect(response.body).not_to include(html(other.member.name))
    end

    it "lists tasks with nobody on them, so somebody can take them" do
      create(:task, team: tenant.team, assignee: nil, title: "Orphaned")
      sign_in tenant.owner

      get people_path

      expect(Nokogiri::HTML(response.body).at_css(".people__unassigned").text).to include("Orphaned")
    end
  end

  describe "a colleague's list" do
    before { sign_in tenant.owner }

    it "shows their tasks and not yours" do
      create(:task, team: tenant.team, assignee: tenant.member, title: "Theirs to do")
      create(:task, team: tenant.team, assignee: tenant.owner, title: "Mine to do")

      get person_path(member_membership)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Theirs to do")
      expect(response.body).not_to include("Mine to do")
    end

    it "is open to a plain member too" do
      create(:task, team: tenant.team, assignee: tenant.owner, title: "The boss's errand")
      sign_in tenant.member

      get person_path(owner_membership)

      expect(response.body).to include("The boss's errand".then { |title| html(title) })
    end

    # A membership id from another team is an id that was never issued here.
    it "returns 404 for a person on another team, rather than 403" do
      other = create_tenant

      get person_path(other.member.membership_for(other.team))

      expect(response).to have_http_status(:not_found)
    end

    it "puts a task added from their list on their list, not yours" do
      get person_path(member_membership)
      expect(Nokogiri::HTML(response.body).at_css("#quick_add input[name='task[assignee_id]']")["value"]).to eq(tenant.member.id.to_s)

      post tasks_path, params: { task: { title: "Fix the navbar", assignee_id: tenant.member.id } }

      expect(tenant.team.tasks.last).to have_attributes(title: "Fix the navbar", assignee: tenant.member, created_by: tenant.owner)
    end
  end

  describe "your own list" do
    it "leaves a colleague's tasks off your dashboard" do
      create(:task, team: tenant.team, assignee: tenant.member, title: "Theirs to do")
      sign_in tenant.owner

      get dashboard_path

      expect(response.body).not_to include("Theirs to do")
    end

    it "leaves a colleague's finished work out of your done pile" do
      create(:task, :done, team: tenant.team, assignee: tenant.member, title: "They shipped it")
      create(:task, :done, team: tenant.team, assignee: tenant.owner, title: "I shipped it")
      sign_in tenant.owner

      get tasks_path

      expect(response.body).to include("I shipped it")
      expect(response.body).not_to include("They shipped it")
    end

    it "puts what you add on your own list" do
      sign_in tenant.member

      post tasks_path, params: { task: { title: "Mine" } }

      expect(tenant.team.tasks.last.assignee).to eq(tenant.member)
    end
  end

  describe "assigning" do
    before { sign_in tenant.member }

    it "moves a task to a colleague's list from the edit form, and lands back on that list" do
      task = create(:task, team: tenant.team, assignee: tenant.member)

      patch task_path(task), params: { task: { assignee_id: tenant.owner.id } }

      expect(task.reload.assignee).to eq(tenant.owner)
      expect(response).to redirect_to(person_path(owner_membership))
    end

    # The id in the form is only a claim. Somebody on another team must never
    # be handed this team's work.
    it "refuses to assign a task to somebody who is not on the team" do
      stranger = create_tenant.member
      task = create(:task, team: tenant.team, assignee: tenant.member)

      patch task_path(task), params: { task: { assignee_id: stranger.id } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(task.reload.assignee).to eq(tenant.member)
    end

    it "refuses to add a task straight onto a stranger's list" do
      stranger = create_tenant.member

      expect { post tasks_path, params: { task: { title: "Smuggled", assignee_id: stranger.id } } }
        .not_to change(Task, :count)
    end
  end
end
