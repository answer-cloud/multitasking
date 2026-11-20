# frozen_string_literal: true

# A task can be put off into the low priority list, under the rest. It is the
# priority flag's opposite, and Task refuses a task that is both.
class AddLowPriorityToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :low_priority, :boolean, default: false, null: false
  end
end
