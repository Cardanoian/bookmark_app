class CreditsController < ApplicationController
  skip_before_action :require_login, only: [ :multimedia ]
  skip_before_action :require_student_ranking_profile, only: [ :multimedia ]
  skip_after_action :verify_authorized, only: [ :multimedia ]

  def multimedia
    @items = MultimediaCredit.all
  end
end
