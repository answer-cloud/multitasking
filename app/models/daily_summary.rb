# frozen_string_literal: true

# A few sentences, written by Claude, on what a team got done in one day.
#
# Written once each evening by Summaries::SummarizeDay and never rewritten, so
# what the done pile shows for a day stays what it said that night. One per
# team per day: the unique index is what makes the evening job safe to run
# twice.
# == Schema Information
#
# Table name: daily_summaries
#
#  id         :bigint           not null, primary key
#  body       :text             not null
#  day        :date             not null
#  task_count :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  team_id    :bigint           not null
#
# Indexes
#
#  index_daily_summaries_on_team_id          (team_id)
#  index_daily_summaries_on_team_id_and_day  (team_id,day) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (team_id => teams.id)
#
class DailySummary < ApplicationRecord
  include TenantScoped

  validates :day, presence: true, uniqueness: { scope: :team_id }
  validates :body, presence: true
  validates :task_count, numericality: { only_integer: true, greater_than: 0 }
end
