# frozen_string_literal: true

# The inbox token moves from the team to each person on it, so a task a hook
# pushes in lands on the list of whoever's hook it was. Nullable here; the
# next two migrations fill it in and then require it.
class AddInboxTokenToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :inbox_token, :string
    add_index :memberships, :inbox_token, unique: true
  end
end
