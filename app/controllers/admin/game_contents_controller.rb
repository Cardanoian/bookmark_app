# 총괄관리자 게임 콘텐츠 에스컬레이션(게임 재구성 Phase 3 §4.5·§4.3). 전국 노출되는 system 풀 퀴즈의
# 악성·오답 콘텐츠를 총괄이 중앙에서 영구 숨김/복원/삭제한다. 담임 대시보드는 자기 학급 신고자 신호만
# 보지만, 총괄은 **전국 관점**(신고된 system 풀 퀴즈 전량)을 본다. 기존 2인 자동숨김(record_report!)은
# 그대로 유지하고, 이 큐는 그 위의 사후 중앙 처리 계층이다.
class Admin::GameContentsController < Admin::BaseController
  PER_PAGE = 25

  before_action :set_quiz, only: [ :hide, :restore, :destroy ]

  # 신고된 system 풀 퀴즈(reported 또는 신고 1건 이상). 전국 관점 검토 큐.
  def index
    scope = Quiz.where(origin: :system)
                .where("reported = ? OR reports_count > 0", true)
                .includes(:book).order(reported: :desc, reports_count: :desc, updated_at: :desc)
    @page, @has_next, @quizzes = paginate(scope, per_page: PER_PAGE)
  end

  # 영구 숨김(reported=true → fetch_ready 제외). 2인 미달로 자동 숨김 안 된 콘텐츠도 총괄이 선제 숨김.
  def hide
    @quiz.update!(reported: true)
    redirect_to admin_game_contents_path, notice: "전국 게임 콘텐츠를 숨겼어요."
  end

  # 복원(reported=false → 다시 플레이 풀에 노출).
  def restore
    @quiz.update!(reported: false)
    redirect_to admin_game_contents_path, notice: "숨김을 해제했어요."
  end

  # 영구 삭제(dependent: :destroy 로 문항·기록·신고도 함께 정리).
  def destroy
    Quiz.transaction do
      @quiz.destroy!
      audit!("admin.game_content_delete", target: @quiz)
    end
    redirect_to admin_game_contents_path, notice: "게임 콘텐츠를 삭제했어요."
  end

  private

  def set_quiz
    @quiz = Quiz.where(origin: :system).find(params[:id])
  end
end
