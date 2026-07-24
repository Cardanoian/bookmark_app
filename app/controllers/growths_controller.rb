class GrowthsController < ApplicationController
  def show
    authorize :profile, :show?
    @timeline = StudentGrowthTimeline.new(current_user)
  end
end
