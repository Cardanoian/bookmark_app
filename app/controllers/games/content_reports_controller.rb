module Games
  # 온디맨드 게임 콘텐츠 신고 접수(무게이트 롤아웃 안전장치, TODO 후속 정밀화).
  # 학생이 플레이 중인 **system(온디맨드) 퀴즈**를 신고하면 1인 1신고로 기록하고, 서로 다른
  # REPORT_HIDE_THRESHOLD(2)명 신고 시 자동 숨김+재생성(ContentProvider.record_report!).
  # 접수는 신고자 학급 담임의 대시보드 "신고된 콘텐츠" 섹션으로 사후 검토된다(교사 알림).
  class ContentReportsController < BaseController
    def create
      quiz = Quiz.published.find(params[:quiz_id])
      # 플레이 경계(밴드/학급 클램프)를 통과해 **볼 수 있는** 콘텐츠만 신고 가능(QuizPolicy#show?).
      authorize quiz, :show?

      # 교사 퀴즈는 교사가 직접 관리하므로 신고(자동 숨김+system 재생성) 대상이 아니다.
      unless quiz.origin == "system"
        return redirect_back fallback_location: games_catalog_path,
                             alert: "이 콘텐츠는 신고 대상이 아니에요."
      end

      result = ContentProvider.record_report!(quiz, current_user)
      redirect_back fallback_location: games_catalog_path, notice: report_notice(result)
    end

    private

    # 실제 접수 결과에 맞춘 정직한 안내(중복 신고/접수/자동 숨김 구분).
    def report_notice(result)
      return "이미 신고한 콘텐츠예요. 알려 줘서 고마워요." unless result[:created]

      if result[:hidden]
        "신고가 접수돼 이 콘텐츠를 숨기고 새로 준비했어요. 고마워요!"
      else
        "신고가 접수됐어요. 선생님이 확인할 거예요. 고마워요!"
      end
    end
  end
end
