# 인기대출 레코드(P6.5). source 로 출처(CSV 업로드/정보나루 API)를 구분한다.
# school_id 가 NULL 이면 전국 집계(정보나루 인기대출), 값이 있으면 학교 DLS CSV.
class LibraryLoan < ApplicationRecord
  belongs_to :school, optional: true

  enum :source, { csv: 0, data4library: 1 }, default: :csv

  validates :book_title, presence: true
  validates :count, numericality: { greater_than_or_equal_to: 0 }
end
