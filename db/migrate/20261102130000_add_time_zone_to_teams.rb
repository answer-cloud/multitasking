# frozen_string_literal: true

class AddTimeZoneToTeams < ActiveRecord::Migration[8.1]
  def change
    add_column :teams, :time_zone, :string, default: "UTC", null: false
  end
end
