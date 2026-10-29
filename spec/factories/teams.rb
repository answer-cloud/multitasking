# frozen_string_literal: true

# == Schema Information
#
# Table name: teams
#
#  id                 :bigint           not null, primary key
#  inbox_token        :string           not null
#  name               :string           not null
#  slug               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  stripe_customer_id :string
#
# Indexes
#
#  index_teams_on_inbox_token         (inbox_token) UNIQUE
#  index_teams_on_slug                (slug) UNIQUE
#  index_teams_on_stripe_customer_id  (stripe_customer_id) UNIQUE
#
FactoryBot.define do
  factory :team do
    sequence(:name) { |n| "Team #{n}" }

    trait :subscribed do
      after(:create) { |team| create(:subscription, team: team) }
    end
  end
end
