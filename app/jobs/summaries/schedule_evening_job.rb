# frozen_string_literal: true

module Summaries
  # Queues the day's summary for every team whose evening has come.
  #
  # Run hourly — see `bin/rails summaries:evening` and README.md. Teams live in
  # different zones, so "the evening" arrives for each at a different hour.
  #
  # It asks again every hour until midnight rather than only at EVENING_HOUR, so
  # a missed hour or a late tick still gets the day written. Each ask is cheap:
  # a day with a summary is skipped here, and a day with nothing done costs the
  # service no call to Claude.
  class ScheduleEveningJob < ApplicationJob
    queue_as :low

    # 9pm, the team's time.
    EVENING_HOUR = 21

    def perform
      Team.find_each do |team|
        now = Time.current.in_time_zone(team.zone)
        next if now.hour < EVENING_HOUR
        next if team.daily_summaries.exists?(day: now.to_date)

        Summaries::SummarizeDayJob.perform_later(team.id, now.to_date.iso8601)
      end
    end
  end
end
