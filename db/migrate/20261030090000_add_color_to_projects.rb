# frozen_string_literal: true

class AddColorToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :color, :string
  end
end
