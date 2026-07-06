class DashboardController < ApplicationController
  def show
    case Current.user.role.to_sym
    when :teacher
      render "dashboard/teacher"
    when :school_admin
      render "dashboard/school_admin"
    when :librarian
      render "dashboard/librarian"
    when :superadmin
      render "dashboard/superadmin"
    else
      render "dashboard/student"
    end
  end
end
