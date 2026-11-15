# frozen_string_literal: true

# Projects are how the team sorts its shared list, so anyone on it may make,
# rename or remove one. Removing a project loses nothing: its tasks stay, just
# unfiled.
class ProjectPolicy < ApplicationPolicy
  def index?   = member?
  def show?    = member?
  def create?  = member?
  def update?  = member?
  def destroy? = member?

  # Hiding only changes your own dashboard, so it needs no more than seeing.
  def hide? = show?

  # Keeping a project from the rest of the team changes what everybody else
  # can see, so it takes an admin.
  def restrict? = admin_or_above?

  # A project kept to admins does not exist for anybody else: not on the
  # projects page, not in a picker, not by its address.
  class Scope < ApplicationPolicy::Scope
    def resolve = scope.visible_to(membership)
  end
end
