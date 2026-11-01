# frozen_string_literal: true

require "rails_helper"

# Dev and test broadcast through other adapters, so production's is never
# loaded here. A gem it cannot use would otherwise show up only as a 500 on
# the first broadcast in production.
RSpec.describe "Action Cable in production" do
  it "can load the adapter it is configured with" do
    adapter = Rails.application.config_for(:cable, env: "production").fetch(:adapter)

    expect { require "action_cable/subscription_adapter/#{adapter}" }.not_to raise_error
  end
end
