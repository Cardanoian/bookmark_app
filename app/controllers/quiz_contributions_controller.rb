# 학생 출제 기여(전국 공유 문제은행 UGC, 게임 재구성 Phase 3 §4.1). 독서활동 화면에서 그 책의
# 문제(객관식·나는 누구게? 힌트)를 낸다 → QuizContribution(status: pending) 저장 → 담임 검토 큐로.
# 작성자·학급은 **서버가 확정**(위조 불가)하고, 밴드는 작성자 학년에서 기본 파생한다(교사 승인 때 조정 가능).
# 승인 전까지는 아무에게도 노출되지 않는다(Quiz/풀 밖 pending 행).
class QuizContributionsController < ApplicationController
  # 유효한 콘텐츠축(2종). 그 외 값은 유형 선택 화면으로 되돌린다.
  AXES = %w[mcq hint_reveal].freeze

  PER_PAGE = 20

  # 내가 낸 문제 모아보기(마이페이지 진입). 조회 범위를 `current_user.quiz_contributions` 로 고정해
  # 위조 파라미터로도 남의 기여에 닿지 않는다(정책은 역할만 판정 — reports#index 관용구).
  # 상태별 개수는 전체 기준으로 따로 세서 페이지를 넘겨도 요약이 흔들리지 않게 한다.
  def index
    authorize QuizContribution, :index?
    @page = [ params[:page].to_i, 1 ].max
    scope = current_user.quiz_contributions
    @status_counts = scope.group(:status).count
    records = scope.includes(:book)
                   .order(created_at: :desc, id: :desc)
                   .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @has_next_page = records.size > PER_PAGE
    @contributions = records.first(PER_PAGE)
  end

  def new
    @book = load_book
    @content_axis = AXES.include?(params[:content_axis]) ? params[:content_axis] : nil
    @contribution = QuizContribution.new(book: @book, content_axis: @content_axis || :mcq)
    authorize @contribution, :new?
  end

  def create
    @book = load_book
    @content_axis = AXES.include?(contribution_params[:content_axis]) ? contribution_params[:content_axis] : nil
    @contribution = QuizContribution.new(
      book: @book, user: current_user, classroom: current_user.classroom,
      content_axis: @content_axis || :mcq,
      band: ReadingDomain.game_band_for(current_user.classroom&.grade),
      payload: build_payload
    )
    authorize @contribution, :create?

    if @content_axis && @contribution.save
      redirect_to reading_activity_path(book_id: @book.id),
                  notice: "문제를 냈어요! 선생님이 확인한 뒤 친구들에게 보여 줄게요."
    else
      @contribution.errors.add(:content_axis, "문제 유형을 골라 주세요.") unless @content_axis
      render :new, status: :unprocessable_entity
    end
  end

  private

  # 등록(비-searched) 도서만 기여 대상 — searched 캐시·미존재 id 는 404.
  def load_book
    Book.where.not(category: :searched).find(params[:book_id] || contribution_params[:book_id])
  end

  # 폼 입력(축별)을 payload JSON 으로 조립한다. answer_number(1-based)는 answer_index(0-based)로 변환.
  def build_payload
    case @content_axis
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
      {}
    end
  end

  # 1-based 정답 번호 → 0-based 인덱스(빈 값·비정수는 nil → 모델 검증이 거부).
  def answer_index_from(value)
    return nil if value.blank?

    value.to_s.match?(/\A\d+\z/) ? value.to_i - 1 : nil
  end

  def contribution_params
    params.fetch(:quiz_contribution, {}).permit(
      :book_id, :content_axis, :prompt, :answer_number, :answer, :explanation,
      choices: [], hints: []
    )
  end
end
