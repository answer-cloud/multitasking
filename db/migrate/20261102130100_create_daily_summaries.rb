# frozen_string_literal: true

class CreateDailySummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_summaries do |t|
      t.references :team, null: false, foreign_key: true
      t.date :day, null: false
      t.text :body, null: false
      t.integer :task_count, null: false
      t.timestamps
    end

    add_index :daily_summaries, %i[team_id day], unique: true
  end
end
