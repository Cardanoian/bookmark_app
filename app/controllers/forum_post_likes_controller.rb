# 게시판 글 좋아요(👍, P5.4). 1인 1좋아요(unique). forum_post.likes_count 를 counter_cache 로
# 증감하고 Turbo Stream 으로 좋아요 버튼/카운트를 갱신한다.
class ForumPostLikesController < ApplicationController
  before_action :set_forum_post

  def create
    @like = @forum_post.forum_post_likes.build(user: current_user)
    authorize @like

    begin
      @like.save
    rescue ActiveRecord::RecordNotUnique
      # 동시 더블클릭이 유니크 인덱스에 걸린 경우 — 이미 좋아요한 것으로 간주해
      # 500 없이 조용히 성공 처리한다(counter_cache 는 재증가하지 않는다).
      @like = @forum_post.forum_post_likes.find_by(user: current_user)
    end

    @forum_post.reload
    respond_with_button
  end

  def destroy
    @like = @forum_post.forum_post_likes.find_by(user: current_user)

    if @like
      authorize @like
      @like.destroy
      @forum_post.reload
    else
      skip_authorization
    end

    respond_with_button
  end

  private

  def set_forum_post
    @forum_post = ForumPost.find(params[:forum_post_id])
  end

  def respond_with_button
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_to @forum_post.topic }
    end
  end
end
