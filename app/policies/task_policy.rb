# frozen_string_literal: true

# Each person has a list, and the lists are the team's to see. Anyone on the
# team may add, finish or remove a task on any of them, and hand one to a
# colleague — a task list you need an admin to tidy is a task list nobody
# tidies.
class TaskPolicy < ApplicationPolicy
  def index?    = member?
  def show?     = member?
  def create?   = member?
  def update?   = member?
  def edit?     = update?
  def complete? = member?
  def destroy?  = member?

  # A task filed under a project kept to admins does not exist for anybody
  # else, whoever's list it is on.
  class Scope < ApplicationPolicy::Scope
    def resolve = scope.visible_to(membership)
  end
end
