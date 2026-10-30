# frozen_string_literal: true

class AddHandoffToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :handed_to, :string
    add_column :tasks, :handed_at, :datetime
  end
end
