# frozen_string_literal: true

class RequireInboxTokenOnMemberships < ActiveRecord::Migration[8.1]
  def change
    change_column_null :memberships, :inbox_token, false
  end
end
