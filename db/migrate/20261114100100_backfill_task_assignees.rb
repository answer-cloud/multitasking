# frozen_string_literal: true

# Every task from before lists were personal goes to whoever added it, if they
# are still on the team. One that a hook pushed in has no such person, so it
# goes to the team's first owner — until now the only one the hooks worked for.
class BackfillTaskAssignees < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE tasks SET assignee_id = COALESCE(
        (SELECT m.user_id FROM memberships m
          WHERE m.team_id = tasks.team_id AND m.user_id = tasks.created_by_id),
        (SELECT m.user_id FROM memberships m
          WHERE m.team_id = tasks.team_id AND m.role = 2
          ORDER BY m.created_at, m.id LIMIT 1)
      )
      WHERE assignee_id IS NULL
    SQL
  end

  # Nothing to undo: the column goes with the migration before this one.
  def down; end
end
