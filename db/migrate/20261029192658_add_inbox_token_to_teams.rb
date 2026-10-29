# frozen_string_literal: true

class AddInboxTokenToTeams < ActiveRecord::Migration[8.1]
  def up
    add_column :teams, :inbox_token, :string
    # Existing teams need a token before the column can be required. Done in
    # SQL rather than through Team so the migration does not depend on a model
    # that may change after it.
    execute "UPDATE teams SET inbox_token = md5(random()::text || id::text)"
    change_column_null :teams, :inbox_token, false
    add_index :teams, :inbox_token, unique: true
  end

  def down
    remove_column :teams, :inbox_token
  end
end
