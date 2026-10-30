# frozen_string_literal: true

class AddPriorityToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :priority, :boolean, null: false, default: false
  end
end
