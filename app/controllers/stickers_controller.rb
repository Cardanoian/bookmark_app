# 문장 스티커 동료평가(P5.3). board_post 의 report 에 스티커를 붙이고
# Turbo Stream 으로 목록에 append 한다.
class StickersController < ApplicationController
  before_action :set_board_post

  def create
    @sticker = @board_post.report.stickers.build(sticker_params.merge(by_user: current_user))
    authorize @sticker

    if @sticker.save
      respond_to do |format|
        format.turbo_stream { render :create }
        format.html { redirect_to @board_post, notice: "스티커를 붙였어요." }
      end
    else
      redirect_to @board_post, alert: @sticker.errors.full_messages.to_sentence
    end
  end

  private

  def set_board_post
    @board_post = BoardPost.find(params[:board_post_id])
  end

  def sticker_params
    params.require(:sticker).permit(:position, :emoji, :label)
  end
end
