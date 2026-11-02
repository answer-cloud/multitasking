# frozen_string_literal: true

module Summaries
  # Writes one team's summary for one day. Safe to run more than once: the
  # service leaves a day that already has one alone.
  class SummarizeDayJob < ApplicationJob
    queue_as :low

    retry_on Anthropic::Errors::RateLimitError, wait: :polynomially_longer, attempts: 5
    retry_on Anthropic::Errors::InternalServerError, wait: :polynomially_longer, attempts: 5
    retry_on Anthropic::Errors::APIConnectionError, wait: :polynomially_longer, attempts: 5

    # The day travels as an ISO date: Sidekiq's strict args refuse a Date.
    def perform(team_id, day)
      team = Team.find_by(id: team_id)
      return if team.nil?

      Summaries::SummarizeDay.call(team: team, day: Date.iso8601(day))
    end
  end
end
