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
    return unless current_user.student?

    # 학생 카드의 진행상황은 **참여한 챌린지만** 표시한다(참여 후 활동만 집계 — 미참여 카드는 목표
    # 배지만 보여 준다). participation 은 카드 수만큼 재조회하지 않도록 한 번에 로드한다.
    # EvaluateProgress(보상 쓰기 부작용)는 목록 렌더에서 절대 호출하지 않는다.
    @participations_by_challenge_id = ChallengeParticipation
      .where(user: current_user, challenge_id: @challenges.map(&:id)).index_by(&:challenge_id)
    @progress_by_challenge = @challenges.index_with do |c|
      participation = @participations_by_challenge_id[c.id]
      next nil unless participation && c.has_goals? && c.active?

      Challenges::ProgressCalculator.new(c, current_user, participation: participation).call
    end
  end

  def show
    # 레코드 기반 authorize — 정책 show? 가 전국+소속학교 경계(Scope 대칭)를 레코드로 판정한다.
    authorize @challenge
    return unless current_user.student?

    # 참여한 학생만 평가·표시한다(참여 원장이 곧 참여 사실이고 joined_at 이 집계 하한).
    @participation = @challenge.challenge_participations.find_by(user: current_user)
    return if @participation.nil?

    Challenges::EvaluateProgress.new(current_user).evaluate(@challenge, participation: @participation)
    @progress = Challenges::ProgressCalculator.new(@challenge, current_user, participation: @participation).call if @challenge.has_goals?
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

    participation = join_participation!(@challenge)
    # 참여 당일 이전 플레이한 게임은 날짜 clamp 로 인정될 수 있어(played_on 은 date) 참여 직후 1회 평가한다.
    Challenges::EvaluateProgress.new(current_user).evaluate(@challenge, participation: participation)
    session[:active_challenge_id] = @challenge.id
    redirect_to new_report_path, notice: "‘#{@challenge.title}’ 챌린지에 참여했어요. 독후감을 써 볼까요?"
  end

  private

  # 참여 원장을 만든다(멱등 — 이미 참여했다면 기존 행을 그대로 쓴다). joined_at 이 진행 집계의 하한이라
  # 재참여로 시작점이 미래로 밀리면 이미 쌓은 진행이 사라지므로 절대 갱신하지 않는다.
  def join_participation!(challenge)
    participation = challenge.challenge_participations.find_or_initialize_by(user: current_user)
    return participation if participation.persisted?

    participation.joined_at = Time.current
    participation.save!
    participation
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # 동시 참여 경합 — 먼저 만들어진 행으로 진행한다.
    challenge.challenge_participations.find_by(user: current_user)
  end

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
