# 전역/학교 챌린지. 조회·참여(학생)에 더해 관리(교직원)와 목표·보상까지 담는 최상위 컨트롤러.
# 미션처럼 정량 목표(독후감 수·게임 수, 목표별 선택 도서)와 정확히-1회 포인트 보상을 설정할 수 있다.
# 관리(new/create/edit/update/destroy)는 per-action Pundit(ChallengePolicy)로 게이트하고,
# scope·school_id 는 폼 입력이 아니라 역할에서 파생한다(apply_scope_from_role, 위조 차단).
class ChallengesController < ApplicationController
  include GoalBooks

  before_action :set_challenge, only: [ :show, :join, :edit, :update, :destroy ]

  GOAL_TYPES = %w[approved_reports game_plays].freeze

  def index
    authorize :challenge, :index?
    @challenges = policy_scope(Challenge).includes(challenge_goals: :books).order(created_at: :desc)
    # 학생 카드에 본인 진행상황을 표시하기 위해 목표 있는 활성 챌린지만 순수 진행률을 계산한다.
    # EvaluateProgress(참여·보상 쓰기 부작용)는 목록 렌더에서 절대 호출하지 않는다.
    if current_user.student?
      @progress_by_challenge = @challenges.index_with do |c|
        (c.has_goals? && c.active?) ? Challenges::ProgressCalculator.new(c, current_user).call : nil
      end
    end
  end

  def show
    # 레코드 기반 authorize — 정책 show? 가 전국+소속학교 경계(Scope 대칭)를 레코드로 판정한다.
    authorize @challenge
    # 뷰어 학생의 진행을 평가(멱등 지연 참여·완료 시 보상)한 뒤 표시용 진행률을 계산한다.
    Challenges::EvaluateProgress.new(current_user).evaluate(@challenge) if current_user.student?
    @progress = Challenges::ProgressCalculator.new(@challenge, current_user).call if current_user.student? && @challenge.has_goals?
    @participation = @challenge.challenge_participations.find_by(user: current_user) if current_user.student?
  end

  def new
    @challenge = Challenge.new(reward_points: 50)
    authorize @challenge
  end

  def create
    @challenge = Challenge.new(challenge_params)
    apply_scope_from_role(@challenge)
    authorize @challenge
    apply_goals(@challenge)

    if @challenge.save
      redirect_to challenge_path(@challenge), notice: "챌린지를 만들었어요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @challenge
  end

  def update
    authorize @challenge
    @challenge.assign_attributes(challenge_params)
    apply_goals(@challenge)

    if @challenge.save
      redirect_to challenge_path(@challenge), notice: "챌린지를 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @challenge
    Challenge.transaction do
      @challenge.destroy!
      audit!("staff.challenge_delete", target: @challenge)
    end
    redirect_to challenges_path, notice: "챌린지를 삭제했어요."
  end

  def join
    authorize :challenge, :join?
    return head :forbidden unless joinable?(@challenge)

    session[:active_challenge_id] = @challenge.id
    redirect_to new_report_path, notice: "‘#{@challenge.title}’ 챌린지에 참여했어요. 독후감을 써 볼까요?"
  end

  private

  def set_challenge
    @challenge = Challenge.includes(challenge_goals: :books).find(params[:id])
  end

  # 제목·소개글·기간·보상만 폼에서 받는다. scope·school_id 는 역할에서 파생(apply_scope_from_role)해 위조를 차단한다.
  def challenge_params
    params.require(:challenge).permit(:title, :description, :starts_on, :ends_on, :reward_points)
  end

  # 관리자 역할에서 scope·school_id 를 확정한다: 총괄=전국(global), 그 외 교직원=우리 학교(school, 본인 소속).
  def apply_scope_from_role(challenge)
    if current_user.superadmin?
      challenge.scope = :global
      challenge.school_id = nil
    else
      challenge.scope = :school
      challenge.school_id = current_user.school_id
    end
  end

  # 고정 2목표(승인 독후감·게임) 폼 입력 → challenge_goals 재구성(미션 apply_goals 미러). target 이 양수인
  # 종류만 목표로 만든다. 종류별로 '여러 책'을 허용목록으로 지정할 수 있고(GoalBooks 가 로컬 id + 원격
  # 검색 isbn 을 해석), 지정하면 그 목록 중 어느 책 활동이든 인정, 비우면 아무 책이나 인정(any-of).
  def apply_goals(challenge)
    challenge.challenge_goals.destroy_all if challenge.persisted?
    challenge.challenge_goals.reset
    GOAL_TYPES.each do |goal_type|
      target = params.dig(:challenge, :goals, goal_type).to_i
      next unless target.positive?

      goal = challenge.challenge_goals.build(goal_type: goal_type, target_count: target)
      resolve_goal_book_ids(:challenge, goal_type).each { |book_id| goal.challenge_goal_books.build(book_id: book_id) }
    end
  end

  def joinable?(challenge)
    challenge.global? || challenge.school_id == current_user.school_id
  end
end
