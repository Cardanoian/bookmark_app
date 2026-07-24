# 우수작 게시판(P5.3). 학생에게는 숨김 글이 제외된다(모더레이션 준비).
class BoardPostsController < ApplicationController
  PER_PAGE = 20

  def index
    authorize :board_post, :index?
    @page = [ params[:page].to_i, 1 ].max
    records = policy_scope(BoardPost)
              .includes(report: [ :user, :book ])
              .order(created_at: :desc)
              .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @has_next_page = records.size > PER_PAGE
    @board_posts = records.first(PER_PAGE)
  end

  def show
    @board_post = BoardPost.find(params[:id])
    authorize @board_post
    @report = @board_post.report
    @stickers = @report.stickers.includes(:by_user).order(:position)
    @sticker = Sticker.new
  end
end
