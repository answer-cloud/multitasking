# frozen_string_literal: true

# == Schema Information
#
# Table name: projects
#
#  id            :bigint           not null, primary key
#  aliases       :string           default([]), not null, is an Array
#  color         :string
#  directory     :string
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#  team_id       :bigint           not null
#
# Indexes
#
#  index_projects_on_created_by_id          (created_by_id)
#  index_projects_on_team_id                (team_id)
#  index_projects_on_team_id_and_directory  (team_id,directory) UNIQUE WHERE (directory IS NOT NULL)
#  index_projects_on_team_id_and_name       (team_id,name)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (team_id => teams.id)
#
FactoryBot.define do
  factory :project do
    team
    sequence(:name) { |n| "Project #{n}" }

    trait :with_directory do
      sequence(:directory) { |n| "/Users/you/code/project-#{n}" }
    end
  end
end
