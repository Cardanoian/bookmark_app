# 이달의 책·행사(P6.5). 사서가 학교 단위로 등록·관리한다. book 은 선택(추천 도서 연결).
class LibraryEvent < ApplicationRecord
  belongs_to :school
  belongs_to :book, optional: true

  validates :title, presence: true
end
