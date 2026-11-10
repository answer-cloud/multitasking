# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connecting Slack" do
  let(:tenant) { create_tenant }

  before do
    with_slack_configured
    sign_in tenant.member
  end

  # Starts the trip to Slack and returns the state it carries.
  def start
    post slack_connection_path
    Rack::Utils.parse_query(URI(response.location).query)["state"]
  end

  def grant(slack_user_id: "U1", token: "xoxp-new")
    slack_answers("oauth.v2.access", team: { id: "T0TEAM", name: "Acme" },
                                     authed_user: { id: slack_user_id, access_token: token, token_type: "user" })
  end

  it "sends the person to Slack asking only for user scopes" do
    post slack_connection_path

    uri = URI(response.location)
    query = Rack::Utils.parse_query(uri.query)
    expect(uri.host).to eq("slack.com")
    expect(query["user_scope"]).to include("reactions:read")
    expect(query).not_to have_key("scope")
    expect(query["redirect_uri"]).to eq(callback_slack_connection_url)
  end

  it "links their Slack to them on this team, with the token encrypted" do
    state = start
    grant

    get callback_slack_connection_path, params: { code: "abc", state: state }

    expect(response).to redirect_to(connection_path)
    connection = tenant.team.slack_connections.sole
    expect(connection).to have_attributes(user: tenant.member, slack_user_id: "U1", slack_team_name: "Acme", access_token: "xoxp-new")
    stored = SlackConnection.connection.select_value("SELECT access_token FROM slack_connections WHERE id = #{connection.id}")
    expect(stored).not_to include("xoxp-new")
  end

  it "refuses a callback whose state it did not start" do
    start
    grant

    get callback_slack_connection_path, params: { code: "abc", state: "forged" }

    expect(SlackConnection.count).to eq(0)
    expect(flash[:alert]).to eq("Slack was not connected.")
  end

  it "refuses a callback with no trip to Slack behind it" do
    grant

    get callback_slack_connection_path, params: { code: "abc", state: "" }

    expect(SlackConnection.count).to eq(0)
  end

  it "replaces an earlier link rather than adding a second" do
    create(:slack_connection, team: tenant.team, user: tenant.member, slack_user_id: "U-old")
    state = start
    grant

    get callback_slack_connection_path, params: { code: "abc", state: state }

    expect(tenant.team.slack_connections.pluck(:slack_user_id)).to eq([ "U1" ])
  end

  it "moves a Slack account linked on another team here" do
    other = create_tenant
    create(:slack_connection, team: other.team, user: tenant.member, slack_user_id: "U1")
    state = start
    grant

    get callback_slack_connection_path, params: { code: "abc", state: state }

    expect(SlackConnection.sole.team).to eq(tenant.team)
  end

  it "shows the connection on the connections page and lets them disconnect" do
    create(:slack_connection, team: tenant.team, user: tenant.member, slack_team_name: "Acme")
    revoke = slack_answers("auth.revoke", revoked: true)

    get connection_path
    expect(response.body).to include("Connected to Acme")

    delete slack_connection_path

    expect(SlackConnection.count).to eq(0)
    expect(revoke).to have_been_requested
  end

  it "does not show or remove a teammate's connection" do
    create(:slack_connection, team: tenant.team, user: tenant.owner, slack_team_name: "Acme")

    get connection_path
    expect(response.body).to include("Connect Slack")

    delete slack_connection_path
    expect(response).to have_http_status(:not_found)
    expect(SlackConnection.count).to eq(1)
  end

  context "when Slack is not set up" do
    before { allow(Rails.configuration.x).to receive(:slack_client_id).and_return(nil) }

    it "shows an admin the app manifest, filled in for this server" do
      sign_in tenant.owner

      get connection_path

      expect(response.body).to include(slack_events_url)
      expect(response.body).to include(callback_slack_connection_url)
      expect(response.body).not_to include("Connect Slack")
    end

    it "tells a member to ask an admin" do
      get connection_path

      expect(response.body).to include("Ask a team admin")
      expect(response.body).not_to include(slack_events_url)
    end
  end
end
