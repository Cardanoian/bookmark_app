class PromoteReviewedSearchedBooks < ActiveRecord::Migration[8.1]
  # 검색 캐시(category: searched)로 유입됐지만 이미 승인 독후감이 붙은 도서를 정식 카탈로그
  # (recommended)로 소급 승격한다. 승인-시점 승격 훅(Teacher::ReviewsController#finalize_approval
  # → Book#promote_from_search!) 도입 이전에 승인된 과거분을 메운다. 이 훅이 없던 동안 승인된
  # searched 도서는 홈 "우리 반 인기 도서"에는 떠도 독서활동 허브·자동완성이 searched 를 배제해
  # 클릭·검색이 막다른 길이었다(피그말리온/공자장 사례). 데이터 전용·멱등(searched 만 대상).
  def up
    Book.reset_column_information
    reviewed_book_ids = Report.where(reviewed: true).where.not(book_id: nil).distinct.pluck(:book_id)
    Book.where(id: reviewed_book_ids, category: Book.categories[:searched])
        .update_all(category: Book.categories[:recommended])
  end

  def down
    # 비가역: 승격 후에는 원래 searched 였는지 판별할 근거가 없다(no-op).
  end
end
