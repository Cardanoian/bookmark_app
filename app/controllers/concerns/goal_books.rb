# 미션·챌린지 목표의 '여러 책' 지정(any-of 허용목록) 공용 해석기. 폼은 목표 종류별로 두 배열을 보낸다:
#   <model>[goal_books][<goal_type>][ids][]   — 로컬 카탈로그에서 고른 book_id 들
#   <model>[goal_books][<goal_type>][isbns][] — "🔍 검색"으로 고른 원격(네이버) 책 isbn 들(제출 시 등록)
# ids 는 비-searched 카탈로그 도서만 통과(위조·searched 캐시 차단), isbns 는 SearchService#register
# (캐시-우선)로 등록 후 promote_from_search! 로 정식 카탈로그 승격해 book_id 로 확정한다(reports 미러).
# 무키·미일치·실패 isbn 은 조용히 탈락(nil degrade)한다.
module GoalBooks
  extend ActiveSupport::Concern

  private

  # scope_key(:mission|:challenge) 목표 종류의 지정 도서 book_id 목록(중복 제거). 없으면 [].
  def resolve_goal_book_ids(scope_key, goal_type)
    raw = params.dig(scope_key, :goal_books, goal_type)
    return [] if raw.blank?

    ids   = Array(raw[:ids]).reject(&:blank?)
    isbns = Array(raw[:isbns]).reject(&:blank?)

    local = Book.where.not(category: :searched).where(id: ids).pluck(:id)
    registered = isbns.filter_map { |isbn| register_and_promote_book_id(isbn) }
    (local + registered).uniq
  end

  # 원격 선택 isbn 을 캐시-우선 등록 + 정식 카탈로그 승격 후 book_id 반환(실패 시 nil).
  def register_and_promote_book_id(isbn)
    book = Books::SearchService.new.register(isbn)
    return nil unless book

    book.promote_from_search!
    book.id
  end
end
