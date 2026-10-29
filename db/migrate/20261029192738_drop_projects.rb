# frozen_string_literal: true

# The example tenant-scoped resource has served its purpose.
class DropProjects < ActiveRecord::Migration[8.1]
  def up
    # if_exists so this is safe on a clone that never ran the original
    # create_projects migration.
    drop_table :projects, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "The example Project resource was removed deliberately. Model your " \
          "own tenant-owned table rather than restoring this one."
  end
end
