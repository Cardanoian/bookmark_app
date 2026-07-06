# 우수작 게시판(P5.3). 학생에게는 숨김 글이 제외된다(모더레이션 준비).
class BoardPostsController < ApplicationController
  def index
    authorize :board_post, :index?
    @board_posts = policy_scope(BoardPost)
                   .includes(report: [ :user, :book ])
                   .order(created_at: :desc)
  end

  def show
    @board_post = BoardPost.find(params[:id])
    authorize @board_post
    @report = @board_post.report
    @stickers = @report.stickers.includes(:by_user).order(:position)
    @sticker = Sticker.new
  end
end
