# frozen_string_literal: true

# == Schema Information
#
# Table name: tasks
#
#  id               :bigint           not null, primary key
#  completed_at     :datetime
#  handed_at        :datetime
#  handed_to        :string
#  last_activity_at :datetime         not null
#  notes            :text
#  position         :integer          default(0), not null
#  priority         :boolean          default(FALSE), not null
#  source           :string           default("typed"), not null
#  title            :string           not null
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  created_by_id    :bigint
#  external_id      :string
#  project_id       :bigint
#  team_id          :bigint           not null
#
# Indexes
#
#  index_tasks_on_created_by_id                       (created_by_id)
#  index_tasks_on_project_id                          (project_id)
#  index_tasks_on_team_id                             (team_id)
#  index_tasks_on_team_id_and_completed_at            (team_id,completed_at)
#  index_tasks_on_team_id_and_source_and_external_id  (team_id,source,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (project_id => projects.id) ON DELETE => nullify
#  fk_rails_...  (team_id => teams.id)
#
FactoryBot.define do
  factory :task do
    team
    sequence(:title) { |n| "Task #{n}" }
    source { "typed" }

    trait :done do
      completed_at { Time.current }
    end

    trait :quiet do
      last_activity_at { 3.days.ago }
    end
  end
end
