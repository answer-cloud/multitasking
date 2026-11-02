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

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if membership.nil?

      scope.all
    end
  end
end
