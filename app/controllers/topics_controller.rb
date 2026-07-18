# 토론방(P5.4 + reading_discussion). 목록은 정책 스코프(자기 학급 + 자기 학교 스코프 토픽)로 제한된다.
# reading_discussion 기능 플래그가 꺼지면 컨트롤러 진입 자체를 막는다(뷰 은닉만으론 URL 직접 요청 불가).
class TopicsController < ApplicationController
  before_action :require_reading_discussion!

  PER_PAGE = 20

  def index
    authorize :topic, :index?
    @page = [ params[:page].to_i, 1 ].max
    records = policy_scope(Topic).includes(:book).order(created_at: :desc)
                .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @has_next_page = records.size > PER_PAGE
    @topics = records.first(PER_PAGE)
    # 교사 개설 폼의 담당 학급 선택지(다학급 담임 대응). 학생은 자기 학급 고정이라 불필요.
    @teacher_classrooms = current_user.teacher? ? Classroom.where(teacher_id: current_user.id).order(:grade, :class_no) : Classroom.none
  end

  def show
    @topic = Topic.find(params[:id])
    authorize @topic
    @forum_posts = @topic.forum_posts.visible.includes(:user).order(:created_at)
    @forum_post = ForumPost.new
    # 목록 좋아요 여부를 한 번에 조회(글별 find_by N+1 방지). 뷰는 이 Set 로 인메모리 판정.
    @liked_post_ids = current_user ? ForumPostLike.where(forum_post: @forum_posts, user: current_user).pluck(:forum_post_id).to_set : Set.new
    # 신고 여부도 한 번에 조회(자기 글·이미 신고한 글은 신고 버튼 숨김).
    @reported_post_ids = current_user ? ForumPostReport.where(forum_post: @forum_posts, user: current_user).pluck(:forum_post_id).to_set : Set.new
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
  # 학생은 자기 학급, 교사는 폼에서 고른 **담당 학급**(소유 검증)으로 classroom_id 를 세운다.
  # 교사는 user.classroom_id 가 nil 이라 그대로 쓰면 고아 토픽이 되므로 별도 해석한다.
  def assign_scope_boundary(topic)
    if topic.school?
      topic.classroom_id = nil
      topic.school_id = current_user.school_id
    else
      topic.classroom_id = resolve_classroom_id
      topic.school_id = nil
    end
  end

  # classroom 스코프의 학급 id 를 역할별로 확정한다. 교사는 담당 학급만 허용(위조·타학급 차단):
  #   명시 선택 → 담당 학급일 때만 그 학급, 아니면 nil(모델 검증이 거부 — 타 학급으로 조용히 바꾸지 않음).
  #   미선택   → 담임이 단일 학급이면 자동 선택, 다학급이면 nil(선택 강제).
  def resolve_classroom_id
    return current_user.classroom_id unless current_user.teacher?

    owned = Classroom.where(teacher_id: current_user.id)
    chosen = params.dig(:topic, :classroom_id).presence
    return owned.exists?(id: chosen) ? chosen : nil if chosen

    owned.count == 1 ? owned.first.id : nil
  end

  def topic_params
    params.require(:topic).permit(:title, :scope, :book_id)
  end
end
