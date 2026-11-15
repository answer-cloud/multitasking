# frozen_string_literal: true

# Each membership has its own now. Rolling back brings the column back with
# new tokens, not the old ones: those live on the owners' memberships.
class RemoveInboxTokenFromTeams < ActiveRecord::Migration[8.1]
  def up
    remove_index :teams, :inbox_token
    remove_column :teams, :inbox_token
  end

  def down
    add_column :teams, :inbox_token, :string
    execute "UPDATE teams SET inbox_token = md5(random()::text || id::text)"
    change_column_null :teams, :inbox_token, false
    add_index :teams, :inbox_token, unique: true
  end
end
