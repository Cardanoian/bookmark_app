# 온디맨드 게임 콘텐츠 신고(무게이트 롤아웃 안전장치). 콘텐츠축 캐시 quiz 당 **1인 1신고**
# (cheer/book_intro_vote 패턴, (quiz, user) unique). quiz.reports_count 를 counter_cache 로
# 증감해 "서로 다른 신고자 수"를 세고, Games::ContentProvider 가 임계 도달 시 숨김+재생성한다.
# 접수 자체는 신고자 학급 담임의 대시보드 "신고된 콘텐츠" 섹션으로 사후 검토 신호가 된다.
class QuizReport < ApplicationRecord
  belongs_to :quiz, counter_cache: :reports_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :quiz_id }
end
