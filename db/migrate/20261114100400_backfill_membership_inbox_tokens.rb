# frozen_string_literal: true

# The team's first owner keeps the team's old token, so the hooks already
# installed carry on working and now land on that person's list. Everybody
# else gets a token of their own.
class BackfillMembershipInboxTokens < ActiveRecord::Migration[8.1]
  # A stand-in for the model, so this runs the same whatever the model
  # becomes later.
  class Membership < ActiveRecord::Base
    self.table_name = "memberships"
  end

  def up
    execute <<~SQL.squish
      UPDATE memberships SET inbox_token = teams.inbox_token
      FROM teams
      WHERE teams.id = memberships.team_id
        AND memberships.id = (
          SELECT m.id FROM memberships m
          WHERE m.team_id = teams.id AND m.role = 2
          ORDER BY m.created_at, m.id LIMIT 1
        )
    SQL

    Membership.where(inbox_token: nil).find_each do |membership|
      membership.update_columns(inbox_token: SecureRandom.base58(24))
    end
  end

  def down; end
end
