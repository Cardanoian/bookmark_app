class ProfilesController < ApplicationController
  def show
    authorize :profile, :show?

    @report_count = current_user.reports.count
    @reviewed_report_count = current_user.reports.where(reviewed: true).count
    @badge_count = current_user.badges.count
    @game_count = current_user.quiz_attempts.count
  end
end
