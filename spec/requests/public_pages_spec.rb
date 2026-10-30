# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public pages" do
  it "renders the landing page for a signed-out visitor" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A SaaS foundation")
  end

  it "sends a signed-in user to their dashboard" do
    user = create(:user, :with_team)
    sign_in user

    get root_path
    expect(response).to redirect_to(dashboard_path)
  end

  it "renders pricing from config/plans.yml" do
    get pricing_path

    expect(response).to have_http_status(:ok)
    Plan.all.each { |plan| expect(response.body).to include(html(plan.name)) }
  end

  it "describes the page for search results and link previews" do
    get root_path
    page = Nokogiri::HTML(response.body)

    expect(page.at("meta[name=description]")["content"]).to eq(Rails.configuration.x.app_description)
    expect(page.at("meta[property='og:title']")["content"]).to eq(page.at("title").text)
    expect(page.at("meta[property='og:image']")["content"]).to eq("http://www.example.com/icon.png")
    expect(page.at("link[rel=manifest]")["href"]).to eq(pwa_manifest_path(format: :json))
  end

  it "serves a manifest that names the app and its icon" do
    get pwa_manifest_path(format: :json)

    manifest = response.parsed_body
    expect(manifest["name"]).to eq(Rails.configuration.x.app_name)
    expect(manifest["description"]).to eq(Rails.configuration.x.app_description)
    expect(manifest["icons"].pluck("src")).to all(eq("/icon.png"))
  end

  it "renders the legal stubs" do
    get terms_path
    expect(response).to have_http_status(:ok)

    get privacy_path
    expect(response).to have_http_status(:ok)
  end
end
