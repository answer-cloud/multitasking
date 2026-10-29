# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :team, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }

      t.string :title, null: false
      t.text :notes
      t.string :source, null: false, default: "typed"
      t.string :url
      # Set by whatever sent the task in — a Claude session id, a Slack message
      # ts — so a second ping about the same thing updates one row.
      t.string :external_id
      t.datetime :last_activity_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :tasks, %i[team_id completed_at]
    add_index :tasks, %i[team_id source external_id], unique: true, where: "external_id IS NOT NULL"
  end
end
