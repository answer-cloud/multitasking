# frozen_string_literal: true

# A project an admin has kept from the rest of the team. On the project, not
# the membership: unlike hiding one from your own list, this is the same for
# everybody.
class AddAdminOnlyToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :admin_only, :boolean, null: false, default: false
  end
end
