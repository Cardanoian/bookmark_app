# 응원(👏, P5.3). 1인 1회(unique). report.cheers_count 카운터를 증감하고
# Turbo Stream 으로 응원 버튼/카운트를 갱신한다.
class CheersController < ApplicationController
  before_action :set_board_post

  def create
    @cheer = @board_post.cheers.build(user: current_user)
    authorize @cheer

    begin
      @board_post.report.increment!(:cheers_count) if @cheer.save
    rescue ActiveRecord::RecordNotUnique
      # 동시 더블클릭이 유니크 인덱스에 걸린 경우 — 이미 응원한 것으로 간주해
      # 500 없이 조용히 성공 처리하고, 카운터는 재증가하지 않는다(중복 카운트 방지).
      @cheer = @board_post.cheers.find_by(user: current_user)
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
