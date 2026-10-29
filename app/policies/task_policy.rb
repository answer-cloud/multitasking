# frozen_string_literal: true

# Tasks are the team's shared to-do list. Anyone on the team may add, finish or
# remove one — a task list you need an admin to tidy is a task list nobody
# tidies.
class TaskPolicy < ApplicationPolicy
  def index?    = member?
  def show?     = member?
  def create?   = member?
  def update?   = member?
  def edit?     = update?
  def complete? = member?
  def destroy?  = member?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if membership.nil?

      scope.all
    end
  end
end
