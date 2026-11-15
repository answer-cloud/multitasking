# frozen_string_literal: true

# Whose list a task is on. Until now the team kept one list between them; from
# here each person has their own, and a task with nobody on it waits on the
# team page for somebody to take it.
class AddAssigneeToTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :tasks, :assignee, foreign_key: { to_table: :users, on_delete: :nullify }, index: false

    # A person's list is always read as "this team, this person, still to do".
    add_index :tasks, %i[team_id assignee_id completed_at]
  end
end
