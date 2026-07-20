# 큐레이션 게임 문항(Stage 2). db/seeds/book_quizzes.yml(Sonnet 팀 검수 문항)을 축별로 담는
# 저장 테이블. 큐레이션이 있는 책은 학생에게 이 검수 문항이 출제되고(Games::ContentProvider 가
# 밴드별로 지연 물질화·서빙, source: curated), 제네릭 오프라인/미검증 AI로 덮이지 않는다.
#   content_axis : 이 모델 전용 정수 매핑(mcq=0 / hint_reveal=1). Quiz enum 과 무관 —
#                  Games::CuratedContent 는 항상 심볼/문자열명으로 넘긴다.
#   payload      : 그 축의 문항 배열(YAML 원본 형태). Games::CuratedContent.set_for 가 소비한다.
class CuratedQuiz < ApplicationRecord
  belongs_to :book

  enum :content_axis, { mcq: 0, hint_reveal: 1 }

  validates :payload, presence: true
  validates :content_axis, uniqueness: { scope: :book_id }
end
