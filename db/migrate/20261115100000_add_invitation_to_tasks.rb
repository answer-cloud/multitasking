# frozen_string_literal: true

# A task can wait on an invitation: given to somebody who has been asked onto
# the team and has not joined yet. Accepting moves it to their list; revoking
# the invitation leaves the task with nobody.
class AddInvitationToTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :tasks, :invitation, foreign_key: { to_table: :team_invitations, on_delete: :nullify }
  end
end
