# 응원(👏, P5.3). 1인 1회(unique). report.cheers_count 카운터를 증감하고
# Turbo Stream 으로 응원 버튼/카운트를 갱신한다.
class CheersController < ApplicationController
  before_action :set_board_post

  def create
    @cheer = @board_post.cheers.build(user: current_user)
    authorize @cheer

    if @cheer.save
      @board_post.report.increment!(:cheers_count)
    end

    respond_with_button
  end

  def destroy
    @cheer = @board_post.cheers.find_by(user: current_user)

    if @cheer
      authorize @cheer
      @cheer.destroy
      report = @board_post.report
      report.decrement!(:cheers_count) if report.cheers_count.positive?
    end

    respond_with_button
  end

  private

  def set_board_post
    @board_post = BoardPost.find(params[:board_post_id])
  end

  def respond_with_button
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_to @board_post }
    end
  end
end
