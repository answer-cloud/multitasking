# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard" do
  include ActiveSupport::Testing::TimeHelpers

  it "requires authentication" do
    get dashboard_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "sends a user with no team to team creation" do
    sign_in create(:user)

    get dashboard_path
    expect(response).to redirect_to(new_team_path)
  end

  it "renders the active team" do
    tenant = create_tenant(name: "Northwind")
    sign_in tenant.owner

    get dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Northwind")
  end

  it "shows what is left to do and what went in the jar today" do
    tenant = create_tenant
    create(:task, team: tenant.team, title: "Still to do")
    create(:task, :done, team: tenant.team, title: "Finished today")
    create(:task, team: tenant.team, completed_at: 2.days.ago, title: "Finished last week")
    sign_in tenant.owner

    get dashboard_path

    expect(response.body).to include("Still to do")
    expect(response.body).to include("Finished today")
    expect(response.body).not_to include("Finished last week")
  end

  it "greets inbox zero with a text face, and hands the page the rest to rotate" do
    tenant = create_tenant
    sign_in tenant.owner

    get dashboard_path

    face = Nokogiri::HTML(response.body).at_css(".checklist-empty__art").text
    faces = JSON.parse(Nokogiri::HTML(response.body).at_css("[data-checklist-faces-value]")["data-checklist-faces-value"])
    expect(TasksHelper::INBOX_ZERO_FACES).to include(face)
    expect(faces).to eq(TasksHelper::INBOX_ZERO_FACES)
  end

  it "shows one list you can drag, by task, unless asked otherwise" do
    tenant = create_tenant
    create(:task, team: tenant.team, title: "Loose end")
    sign_in tenant.owner

    get dashboard_path

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("ul#tasks[data-controller=sortable] .checklist__title").text).to eq("Loose end")
    expect(page.at_css(".today__views [aria-current=page]").text).to eq("By task")
    expect(page.at_css(".task-group")).to be_nil
  end

  it "groups what is left by project, A to Z, with Other last" do
    tenant = create_tenant
    zoo = create(:project, team: tenant.team, name: "Zoo")
    api = create(:project, team: tenant.team, name: "api")
    create(:task, team: tenant.team, title: "Loose end")
    create(:task, team: tenant.team, project: zoo, title: "Feed the lions")
    create(:task, team: tenant.team, project: api, title: "Ship the endpoint")
    create(:task, team: tenant.team, project: api, title: "Write the docs")
    sign_in tenant.owner

    get dashboard_path(view: "projects")

    page = Nokogiri::HTML(response.body)
    groups = page.css(".task-groups > .task-group")
    expect(groups.map { |group| group.at_css(".task-group__head").text.strip }).to eq(%w[api Zoo Other])
    expect(groups.map { |group| group["data-project-id"] }).to eq([ api.id.to_s, zoo.id.to_s, "" ])
    expect(groups.first.css(".checklist__title").map(&:text)).to eq([ "Write the docs", "Ship the endpoint" ])
    # New tasks stream into #tasks; grouped_controller.js files them from there.
    expect(page.at_css(".task-groups > ul#tasks[hidden]")).to be_present
    # The priority list still drags; a place in one project's list does not.
    expect(page.at_css(".task-groups [data-controller=sortable]")).to be_nil
  end

  it "remembers the view you picked, and ignores one it does not know" do
    tenant = create_tenant
    create(:task, team: tenant.team)
    sign_in tenant.owner

    get dashboard_path(view: "projects")
    get dashboard_path
    expect(Nokogiri::HTML(response.body).at_css(".today__views [aria-current=page]").text).to eq("By project")

    get dashboard_path(view: "nonsense")
    expect(Nokogiri::HTML(response.body).at_css(".today__views [aria-current=page]").text).to eq("By project")

    get dashboard_path(view: "tasks")
    expect(Nokogiri::HTML(response.body).at_css(".today__views [aria-current=page]").text).to eq("By task")
  end

  it "only shows this team's tasks when grouped" do
    tenant = create_tenant
    other = create_tenant
    create(:task, team: other.team, title: "Someone else's", project: create(:project, team: other.team, name: "Theirs"))
    sign_in tenant.owner

    get dashboard_path(view: "projects")

    expect(response.body).not_to include("Someone else's")
    expect(response.body).not_to include("Theirs")
  end

  it "lists what got done today newest first, each under its project" do
    # Midday, so two hours ago is still today.
    travel_to Time.utc(2026, 10, 29, 12, 0) do
      tenant = create_tenant
      create(:task, :done, team: tenant.team, title: "Earlier", completed_at: 2.hours.ago,
        project: create(:project, team: tenant.team, name: "Zoo"))
      create(:task, :done, team: tenant.team, title: "Later", completed_at: 1.hour.ago)
      sign_in tenant.owner

      get dashboard_path

      done = Nokogiri::HTML(response.body).css("#done_today .checklist__item")
      expect(done.map { |row| row.at_css(".checklist__title").text }).to eq(%w[Later Earlier])
      expect(done.map { |row| row.at_css(".checklist__project").text.strip }).to eq(%w[Other Zoo])
    end
  end

  it "links a pushed task back to its conversation in the agent's app" do
    tenant = create_tenant
    create(:task, team: tenant.team, source: "claude", url: "claude://code/continue?session=local_abc-123")
    sign_in tenant.owner

    get dashboard_path

    expect(response.body).to include('href="claude://code/continue?session=local_abc-123"')
    expect(response.body).to include("Open in Claude ↗")
  end

  it "sends a click on a project back to where its latest linked task came from" do
    tenant = create_tenant
    project = create(:project, team: tenant.team, name: "Api", directory: "/code/api")
    create(:task, team: tenant.team, project: project, url: "https://github.com/acme/api/pull/1", last_activity_at: 1.day.ago)
    create(:task, team: tenant.team, project: project, source: "claude",
      url: "claude://code/continue?session=local_latest", last_activity_at: 1.hour.ago)
    create(:task, team: tenant.team, project: project, source: "voice", last_activity_at: 1.minute.ago)
    sign_in tenant.owner

    get dashboard_path

    # The spoken task is newest but has no link, so the Claude session wins.
    expect(response.body.scan(%r{<a class="project-tag[^"]*" title="Back to: [^"]*" href="claude://code/continue\?session=local_latest">Api</a>}).size).to eq(3)
  end

  it "opens a web link from a project in a new tab, like the task's own button" do
    tenant = create_tenant
    project = create(:project, team: tenant.team, name: "Site")
    create(:task, team: tenant.team, project: project, url: "https://example.com/brief")
    sign_in tenant.owner

    get dashboard_path

    expect(response.body).to match(%r{<a class="project-tag[^"]*" target="_blank" rel="noopener noreferrer" title="Back to: [^"]*" href="https://example.com/brief">Site</a>})
  end

  it "leaves a project with no linked tasks as plain text" do
    tenant = create_tenant
    project = create(:project, team: tenant.team, name: "Api", directory: "/code/api")
    create(:task, team: tenant.team, project: project)
    sign_in tenant.owner

    get dashboard_path

    expect(response.body).not_to include(">Api</a>")
    expect(response.body).not_to include("claude://code/new")
  end

  it "puts today's done count where the brand was" do
    tenant = create_tenant
    create(:task, :done, team: tenant.team)
    create(:task, team: tenant.team, completed_at: 2.days.ago)
    sign_in tenant.owner

    get dashboard_path

    expect(response.body).to include(%(Done <span class="tally numeric" data-done-count>1</span>))
  end

  it "names the talk shortcut the way the keyboard does" do
    tenant = create_tenant
    sign_in tenant.owner

    get dashboard_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" }
    expect(response.body).to include("<kbd>⌘⇧V</kbd>")

    get dashboard_path, headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
    expect(response.body).to include("<kbd>Ctrl+Shift+V</kbd>")
  end

  it "tells the time in the browser's time zone, not the server's" do
    tenant = create_tenant
    create(:task, team: tenant.team, title: "Early start", completed_at: Time.utc(2026, 10, 29, 19, 30))
    sign_in tenant.owner
    cookies[:time_zone] = "Pacific/Auckland"

    travel_to Time.utc(2026, 10, 29, 20, 0) do
      get dashboard_path
    end

    expect(response.body).to include("Good morning")
    expect(response.body).to include("Friday 30 October")
    expect(response.body).to include(">08:30</time>")
  end

  it "falls back to UTC when the browser names a zone that does not exist" do
    tenant = create_tenant
    sign_in tenant.owner
    cookies[:time_zone] = "Mars/Olympus_Mons"

    travel_to Time.utc(2026, 10, 29, 20, 0) do
      get dashboard_path
    end

    expect(response.body).to include("Good evening")
  end
end
