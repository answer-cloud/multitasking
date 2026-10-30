# frozen_string_literal: true

# Projects come back, this time for real: the folder or product a task belongs
# to. The template's example table of the same name was dropped earlier, so this
# one needs a name of its own.
class RecreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :team, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }

      t.string :name, null: false
      # The folder an agent works in — a repository root — so a task pushed in
      # from a session there files itself under this project.
      t.string :directory

      t.timestamps
    end

    add_index :projects, %i[team_id name]
    add_index :projects, %i[team_id directory], unique: true, where: "directory IS NOT NULL"
  end
end
