# frozen_string_literal: true

FactoryBot.define do
  factory :slack_connection do
    team
    user { association :user }
    slack_team_id { "T0TEAM" }
    slack_team_name { "Acme" }
    sequence(:slack_user_id) { |n| "U#{n.to_s.rjust(6, "0")}" }
    access_token { "xoxp-test-token" }
  end
end
