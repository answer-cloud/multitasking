# frozen_string_literal: true

# The evening summaries are read-only. Anyone on the team may read them; only
# Summaries::SummarizeDay writes them, so there is nothing here to permit.
class DailySummaryPolicy < ApplicationPolicy
  def index?   = member?
  def show?    = member?
  def create?  = false
  def update?  = false
  def destroy? = false

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if membership.nil?

      scope.all
    end
  end
end
