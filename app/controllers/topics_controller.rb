# 토론방(P5.4). 목록은 정책 스코프(자기 학급 + 자기 학교 스코프 토픽)로 제한된다.
class TopicsController < ApplicationController
  PER_PAGE = 20

  def index
    authorize :topic, :index?
    @page = [ params[:page].to_i, 1 ].max
    records = policy_scope(Topic).includes(:book).order(created_at: :desc)
                .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @has_next_page = records.size > PER_PAGE
    @topics = records.first(PER_PAGE)
  end

  def show
    @topic = Topic.find(params[:id])
    authorize @topic
    @forum_posts = @topic.forum_posts.visible.includes(:user).order(:created_at)
    @forum_post = ForumPost.new
    # 목록 좋아요 여부를 한 번에 조회(글별 find_by N+1 방지). 뷰는 이 Set 로 인메모리 판정.
    @liked_post_ids = current_user ? ForumPostLike.where(forum_post: @forum_posts, user: current_user).pluck(:forum_post_id).to_set : Set.new
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
