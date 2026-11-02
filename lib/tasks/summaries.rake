# frozen_string_literal: true

namespace :summaries do
  # Hatchbox runs this every hour, on the hour. It only queues work; Sidekiq
  # does the writing. See Summaries::ScheduleEveningJob.
  desc "Queue the day's summary for every team whose evening has come"
  task evening: :environment do
    Summaries::ScheduleEveningJob.perform_now
  end
end
