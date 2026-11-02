# frozen_string_literal: true

class AddHiddenProjectIdsToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :hidden_project_ids, :bigint, array: true, default: [], null: false
  end
end
