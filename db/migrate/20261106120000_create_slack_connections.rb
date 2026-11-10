# frozen_string_literal: true

class CreateSlackConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_connections do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :slack_team_id, null: false
      t.string :slack_team_name
      t.string :slack_user_id, null: false
      t.text :access_token, null: false
      t.timestamps
    end

    # One Slack account feeds one team, and a person links one Slack account
    # per team. Reconnecting replaces rather than adds.
    add_index :slack_connections, %i[slack_team_id slack_user_id], unique: true
    add_index :slack_connections, %i[team_id user_id], unique: true
  end
end
