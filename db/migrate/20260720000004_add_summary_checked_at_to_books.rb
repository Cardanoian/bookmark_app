# Gemini 줄거리 생성 확신 게이트 캐시(게임 재구성 Phase 4, §1·§3.1). AI 퀴즈 워밍 프롬프트에
# 주입되는 book.summary 가 대다수 시드 도서에서 NULL 이라 제목만으로 문제를 지어내던 근본 문제를,
# "Gemini 가 아는 유명·고전 책의 줄거리를 백그라운드에서 생성해 채우는" 것으로 해결한다.
#
# summary_checked_at = **비파생 LLM 판정 결과 캐시**("Gemini 확인을 이미 시도함"). summary 가
# 여전히 blank 인데 checked_at 이 있으면 = Gemini 가 모르는 책(환각 방지로 저장 안 함, 재확인 안 함).
# 무키에서는 세팅하지 않아(BookSummaryJob no-op) 키가 생기면 나중에 재시도된다. 순수 additive.
class AddSummaryCheckedAtToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :summary_checked_at, :datetime
  end
end
