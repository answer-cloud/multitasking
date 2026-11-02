# frozen_string_literal: true

FactoryBot.define do
  factory :daily_summary do
    team
    day { Date.current }
    body { "A tidy day: the invoice went out and the deck got its last pass." }
    task_count { 2 }
  end
end
