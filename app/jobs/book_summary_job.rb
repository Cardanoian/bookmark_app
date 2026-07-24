# Gemini 줄거리 생성 백그라운드 잡(게임 재구성 Phase 4, §1c). BookEnrichmentJob 미러.
# AI 퀴즈 워밍이 접지 콘텐츠를 만들 수 있도록 book.summary 를 채운다. 아동 대면이 아니라
# 백그라운드이므로 무대기 불변식과 무관하고, 무키에서는 아무 것도 하지 않는다(크래시 0).
#
# 계약:
#   - **멱등**: 이미 summary 가 있거나(book.summary.present?) 이미 Gemini 확인을 시도한
#     (book.summary_checked_at.present?) 책은 손대지 않는다(재실행·경쟁·재확인 방지).
#   - **무키 no-op**: GeminiClient 미설정이면 checked_at 을 세팅하지 않고 즉시 반환한다 —
#     키가 나중에 생기면 다시 시도되도록(무명 마킹으로 영구 차단하지 않는다).
#   - 키 있음: 서비스가 확신 있는 줄거리를 주면 summary+checked_at 저장, nil 이면(모르는 책)
#     checked_at 만 저장해 재확인을 막는다(환각 방지로 summary 는 채우지 않음).
class BookSummaryJob < ApplicationJob
  queue_as :default

  def perform(book_id)
    book = Book.find_by(id: book_id)
    return if book.nil?
    return if book.summary.present? || book.summary_checked_at.present? # 멱등 skip
    return unless Ai::GeminiClient.new.configured? # 무키 → checked_at 미세팅(키 생기면 재시도)

    summary = Ai::BookSummaryService.new.call(book)
    if summary.present?
      book.update(summary: summary, summary_checked_at: Time.current)
    else
      book.update(summary_checked_at: Time.current) # 모르는 책 마킹(재확인 방지)
    end
  end
end
