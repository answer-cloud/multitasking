# frozen_string_literal: true

class AddProjectToTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :tasks, :project, foreign_key: { on_delete: :nullify }
  end
end
