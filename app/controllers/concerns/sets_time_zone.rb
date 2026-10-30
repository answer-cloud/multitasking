# frozen_string_literal: true

# Runs each request in the browser's own time zone, so "today", the greeting
# and the time a task went in the jar match the clock on the wall. The layout
# writes the zone into a cookie; an unknown or missing one falls back to UTC.
module SetsTimeZone
  extend ActiveSupport::Concern

  included do
    around_action :use_browser_time_zone
  end

  private

  def use_browser_time_zone(&)
    Time.use_zone(ActiveSupport::TimeZone[cookies[:time_zone].to_s] || Time.zone_default, &)
  end
end
