# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Filing a task under a project" do
  let(:tenant) { create_tenant }
  let!(:task) { create(:task, :quiet, team: tenant.team) }
  let!(:project) { create(:project, team: tenant.team, name: "Storefront") }

  before { sign_in tenant.member }

  it "files the task and updates the chip in its row" do
    patch task_project_path(task), params: { task: { project_id: project.id } }, as: :turbo_stream

    expect(task.reload.project).to eq(project)
    expect(response.body).to include(%(action="replace" target="project_task_#{task.id}"))
    expect(response.body).to include("Storefront")
  end

  it "takes the task out of its project when the choice is blank" do
    task.update!(project: project)

    patch task_project_path(task), params: { task: { project_id: "" } }, as: :turbo_stream

    expect(task.reload.project).to be_nil
  end

  # Sorting the list is not working on the task.
  it "does not count as activity, so a quiet task stays quiet" do
    patch task_project_path(task), params: { task: { project_id: project.id } }, as: :turbo_stream

    expect(task.reload).to be_quiet
  end

  it "works without JavaScript" do
    patch task_project_path(task), params: { task: { project_id: project.id } }

    expect(response).to have_http_status(:see_other)
    expect(task.reload.project).to eq(project)
  end

  # The project is looked up through the team, so another team's is not found
  # — not forbidden, which would confirm it exists.
  it "returns 404 for another team's project and leaves the task alone" do
    theirs = create(:project)

    patch task_project_path(task), params: { task: { project_id: theirs.id } }, as: :turbo_stream

    expect(response).to have_http_status(:not_found)
    expect(task.reload.project).to be_nil
  end

  it "returns 404 for another team's task" do
    theirs = create(:task)

    patch task_project_path(theirs), params: { task: { project_id: project.id } }, as: :turbo_stream

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.project).to be_nil
  end

  it "offers the team's projects in each row of the list" do
    create(:project, name: "Their secret project")

    get dashboard_path

    expect(response.body).to include(%(<option value="#{project.id}">Storefront</option>))
    expect(response.body).not_to include("Their secret project")
  end
end
