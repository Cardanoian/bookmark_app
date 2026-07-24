class ProfilePolicy < ApplicationPolicy
  def show?
    user&.student?
  end
end
