# frozen_string_literal: true

class AddAliasesToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :aliases, :string, array: true, default: [], null: false
  end
end
