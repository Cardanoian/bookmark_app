class Book < ApplicationRecord
  # 학년밴드 표준 라벨(게임 밴드 g12/g34/g56 과 정합). grade_band 는 표시·필터 전용이며
  # 게임 밴드(학생 학년에서 ReadingDomain.game_band_for 로 파생)와는 무관하다(계획 §3.1).
  GRADE_BANDS = [ "초등 1~2", "초등 3~4", "초등 5~6" ].freeze

  has_many :reports, dependent: :nullify

  enum :category, { recommended: 0, classic: 1, searched: 2 }, default: :recommended

  validates :title, presence: true
  # isbn 유일성(공란 허용) — DB 부분 유니크 인덱스(index_books_on_isbn, WHERE isbn IS NOT NULL
  # AND isbn != '')와 짝을 이루는 소프트 게이트. 인덱스는 동시성까지 막는 하드 백스톱이고,
  # 이 검증은 admin/books 등 폼 경로에서 중복 isbn 을 500(RecordNotUnique) 대신 폼 에러로
  # 강등한다. allow_blank 로 텍스트-only(공란 isbn) 도서는 인덱스 술어와 동일하게 제약 밖.
  validates :isbn, uniqueness: { allow_blank: true }
end
