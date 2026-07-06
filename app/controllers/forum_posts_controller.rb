# 토론 글 작성(P5.4). 토픽 경계 안 사용자만 글을 남길 수 있다(ForumPostPolicy).
class ForumPostsController < ApplicationController
  before_action :set_topic

  def create
    @forum_post = @topic.forum_posts.build(forum_post_params.merge(user: current_user))
    authorize @forum_post

    if @forum_post.save
      redirect_to @topic, notice: "글을 남겼어요."
    else
      redirect_to @topic, alert: @forum_post.errors.full_messages.to_sentence
    end
  end

  private

  def set_topic
    @topic = Topic.find(params[:topic_id])
  end

  def forum_post_params
    params.require(:forum_post).permit(:text)
  end
end
