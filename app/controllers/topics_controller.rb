# 토론방(P5.4). 목록은 정책 스코프(자기 학급 + 자기 학교 스코프 토픽)로 제한된다.
class TopicsController < ApplicationController
  def index
    authorize :topic, :index?
    @topics = policy_scope(Topic).includes(:book).order(created_at: :desc)
  end

  def show
    @topic = Topic.find(params[:id])
    authorize @topic
    @forum_posts = @topic.forum_posts.visible.includes(:user).order(:created_at)
    @forum_post = ForumPost.new
  end

  def create
    @topic = Topic.new(topic_params)
    assign_scope_boundary(@topic)
    authorize @topic

    if @topic.save
      redirect_to @topic, notice: "토론방을 열었어요."
    else
      redirect_to topics_path, alert: @topic.errors.full_messages.to_sentence
    end
  end

  private

  # 생성자의 소속으로 스코프 경계를 고정한다(다른 학급/학교 토픽 생성 방지).
  def assign_scope_boundary(topic)
    if topic.school?
      topic.classroom_id = nil
      topic.school_id = current_user.school_id
    else
      topic.classroom_id = current_user.classroom_id
      topic.school_id = nil
    end
  end

  def topic_params
    params.require(:topic).permit(:title, :scope, :book_id)
  end
end
