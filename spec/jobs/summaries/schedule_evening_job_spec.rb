# frozen_string_literal: true

require "rails_helper"

RSpec.describe Summaries::ScheduleEveningJob do
  include ActiveSupport::Testing::TimeHelpers

  # 9:30pm in London, 1:30pm in California.
  around { |example| travel_to(Time.utc(2026, 11, 2, 21, 30)) { example.run } }

  let!(:london) { create(:team, time_zone: "London") }
  let!(:california) { create(:team, time_zone: "Pacific Time (US & Canada)") }

  it "queues the day for a team whose evening has come, and not for one still in its afternoon" do
    described_class.perform_now

    expect(Summaries::SummarizeDayJob).to have_been_enqueued.with(london.id, "2026-11-02").exactly(:once)
    expect(Summaries::SummarizeDayJob).not_to have_been_enqueued.with(california.id, anything)
  end

  it "skips a team whose day is already written" do
    create(:daily_summary, team: london, day: Date.new(2026, 11, 2))

    expect { described_class.perform_now }.not_to have_enqueued_job(Summaries::SummarizeDayJob)
  end
end
