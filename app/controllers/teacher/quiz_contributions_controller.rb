# 학생 기여 문제 검토·수정 큐(게임 재구성 Phase 3 §4.3·§4.4). **담임만** 자기 학급 학생의 pending
# 기여를 열람·수정·승인·반려한다(경계는 owned_student! 로 강제 — 크로스-학급 403). 승인하면
# Games::ContributionPublisher 가 최종 페이로드를 system·global·band 풀 퀴즈로 물질화해 전국 공유 풀에
# 편입한다(§4.4). 반려는 미편입. Quiz 편집권과 정합(QuizPolicy manage? = 교사·총괄).
class Teacher::QuizContributionsController < Teacher::BaseController
  BANDS = %w[g12 g34 g56].freeze

  before_action :set_contribution, only: [ :update, :approve, :reject ]

  def index
    @contributions = pending_scope
  end

  # 문항 내용 수정 + 밴드 지정(승인 없이 저장).
  def update
    owned_student!(@contribution.user)
    apply_edits!(@contribution)

    if @contribution.save
      redirect_to teacher_quiz_contributions_path, notice: "학생 문제를 저장했어요."
    else
      @contributions = pending_scope
      render :index, status: :unprocessable_entity
    end
  end

  # 승인 → 전국 공유 풀 편입(물질화). approve 버튼은 독립 button_to(필드 없음)라 **현재 저장된
  # 페이로드/밴드**를 그대로 물질화한다 — 내용을 고칠 게 있으면 먼저 저장(update)한 뒤 승인하는
  # 2스텝(뷰의 수정 폼과 승인 버튼이 형제 폼으로 분리돼 있다, BLOCKER 수정).
  def approve
    owned_student!(@contribution.user)
    @contribution.status = :approved
    @contribution.reviewed_by = Current.user

    if publish_and_approve
      redirect_to teacher_quiz_contributions_path, notice: "승인했어요. 이 문제가 전국 친구들의 문제은행에 들어갔어요."
    else
      @contribution.status = :pending
      @contributions = pending_scope
      render :index, status: :unprocessable_entity
    end
  end

  # 반려 → 미편입(status: rejected).
  def reject
    owned_student!(@contribution.user)
    @contribution.update!(status: :rejected, reviewed_by: Current.user)
    redirect_to teacher_quiz_contributions_path, notice: "반려했어요. 이 문제는 편입되지 않아요."
  end

  private

  def set_contribution
    @contribution = QuizContribution.find(params[:id])
  end

  # 담임 학급 학생들의 pending 기여(총괄은 전체 학급). 검토 큐.
  def pending_scope
    student_ids = User.where(classroom_id: teacher_classrooms.select(:id), role: :student).select(:id)
    QuizContribution.pending.where(user_id: student_ids)
                    .includes(:user, :book).order(:created_at)
  end

  # 검증 후 물질화 + approved 저장을 한 트랜잭션으로. 페이로드 무효면 물질화하지 않고 false.
  #
  # `valid?` 는 `QuizContribution#payload_shape` 만 본다. 물질화는 거기서 `QuizQuestion` 을 만드는데
  # 두 검증이 완전히 같다는 보장은 없다(보기 중복처럼 미러해 둔 규칙도 언젠가 어긋날 수 있다).
  # 어긋나면 `publish!` 의 `save!` 가 RecordInvalid 로 터져 **담임의 승인 클릭이 500** 이 된다 —
  # 학생 입력의 문제를 교사 화면의 장애로 갚는 꼴이라, 여기서 잡아 422 안내로 돌린다.
  def publish_and_approve
    return false unless @contribution.valid?

    ApplicationRecord.transaction do
      Games::ContributionPublisher.publish!(@contribution)
      @contribution.save!
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("ContributionPublisher rejected contribution #{@contribution.id}: #{e.message}")
    @contribution.errors.add(:payload, "이 문제는 문제은행 규칙에 맞지 않아요. 내용을 고친 뒤 다시 승인해 주세요.")
    false
  end

  # 교사 수정 반영(밴드 + 축별 페이로드) — **update 전용**(approve 는 형제 폼의 독립 button_to 라
  # 페이로드 필드를 보내지 않는다, BLOCKER 수정). 축은 학생이 고른 유형이라 바꾸지 않는다.
  # payload_submitted? 가드는 update 요청에 페이로드 필드가 부분 누락된 경우에도 기존 값을
  # 보존해 빈 파라미터로 덮어써 무효화하지 않도록 한다.
  def apply_edits!(contribution)
    band = contribution_params[:band]
    contribution.band = band if BANDS.include?(band)
    contribution.payload = build_payload(contribution.content_axis) if payload_submitted?
  end

  # 페이로드 관련 필드가 폼에서 하나라도 넘어왔는지(수정 의도) 판정.
  def payload_submitted?
    %i[prompt choices answer_number answer hints explanation].any? { |key| contribution_params.key?(key) }
  end

  def build_payload(axis)
    case axis
    when "mcq"
      {
        prompt: contribution_params[:prompt].to_s.strip,
        choices: Array(contribution_params[:choices]).map { |c| c.to_s.strip },
        answer_index: answer_index_from(contribution_params[:answer_number]),
        explanation: contribution_params[:explanation].to_s.strip
      }
    when "hint_reveal"
      {
        answer: contribution_params[:answer].to_s.strip,
        hints: Array(contribution_params[:hints]).map { |h| h.to_s.strip }.reject(&:blank?),
        explanation: contribution_params[:explanation].to_s.strip
      }
    else
      @contribution.payload
    end
  end

  def answer_index_from(value)
    return nil if value.blank?

    value.to_s.match?(/\A\d+\z/) ? value.to_i - 1 : nil
  end

  def contribution_params
    params.fetch(:quiz_contribution, {}).permit(
      :band, :prompt, :answer_number, :answer, :explanation, choices: [], hints: []
    )
  end
end
