require "test_helper"

# 책 발견("이 책은 어때요?") — 주입 PopularDiscovery 풀 샘플링(복원추출·active 제외·distinct·
# 삭제 id top-up) vs 풀 부재 시 기존 추천/클래식 회전 폴백. more_discovery_books? 게이팅도 커버.
class StudentHomeQueryTest < ActiveSupport::TestCase
  # 주입용 스텁 — pool_book_ids(band) 는 band 를 무시하고 미리 정해둔 id 배열만 돌려준다
  # (밴드 판별 자체는 reading_domain_test 가 별도로 커버).
  StubPopularDiscovery = Struct.new(:pool_ids) do
    def pool_book_ids(_band)
      pool_ids
    end
  end

  setup do
    @school = School.create!(name: "홈쿼리초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "홈쿼리학생", password: "password")
  end

  def query_with_pool(pool_ids)
    StudentHomeQuery.new(@student, popular_discovery: StubPopularDiscovery.new(pool_ids))
  end

  # --- 풀 경로: 샘플·active 제외·distinct·크기 ≤6·전부 풀의 부분집합 ---

  test "discovery_books samples from the injected pool (≤6, distinct, subset of pool), excluding active books" do
    books = (1..10).map { |i| Book.create!(title: "발견#{i}", author: "작가", category: :recommended) }
    active_book = books.first
    Report.create!(user: @student, classroom: @classroom, book: active_book, book_title: active_book.title, reviewed: true)

    query = query_with_pool(books.map(&:id))
    result = query.discovery_books

    assert_equal 6, result.size, "후보(9권)가 BOOK_LIMIT(6) 보다 많으면 정확히 6권을 채운다"
    ids = result.map(&:id)
    assert_equal ids.uniq.size, ids.size, "그리드 내 distinct"
    assert ids.all? { |id| books.map(&:id).include?(id) }, "결과는 전부 풀의 부분집합이어야 한다"
    assert_not_includes ids, active_book.id, "이미 활동(독후감)한 책은 발견에서 제외한다"
  end

  test "discovery_books also excludes books the student has already gamed" do
    books = (1..8).map { |i| Book.create!(title: "게임발견#{i}", author: "작가", category: :recommended) }
    gamed_book = books.first
    @student.game_plays.create!(game_type: :quiz, book: gamed_book, played_on: Date.current)

    query = query_with_pool(books.map(&:id))
    result = query.discovery_books

    assert_not_includes result.map(&:id), gamed_book.id
  end

  # --- 삭제된(존재하지 않는) id 가 풀에 섞여도 크래시 없이 살아있는 후보로 top-up ---

  test "discovery_books tops up when the pool contains deleted book ids (no crash, fills from the rest)" do
    books = (1..7).map { |i| Book.create!(title: "발견삭제#{i}", author: "작가", category: :recommended) }
    deleted_ids = [ 999_001, 999_002, 999_003 ] # DB 에 존재하지 않는 id(삭제됨을 가정)
    pool_ids = deleted_ids + books.map(&:id)

    query = query_with_pool(pool_ids)
    result = query.discovery_books

    assert_equal 6, result.size, "삭제 id 를 흡수하고 잔여 후보(7권)에서 top-up 재추출로 채운다"
    assert result.map(&:id).all? { |id| books.map(&:id).include?(id) }
  end

  test "discovery_books returns fewer than BOOK_LIMIT when even top-up cannot fill (small pool, no crash)" do
    books = (1..3).map { |i| Book.create!(title: "소량발견#{i}", author: "작가", category: :recommended) }
    pool_ids = [ 999_001, 999_002 ] + books.map(&:id) # 유효 후보가 3권뿐

    query = query_with_pool(pool_ids)
    result = query.discovery_books

    assert_equal 3, result.size, "잔여 후보 소진 시 더 적게 허용한다(크래시 없음)"
  end

  # --- 폴백: 풀이 비면 기존 추천/클래식 회전 경로로 넘어간다(기존 동작) ---

  test "discovery_books falls back to the existing recommended/classic rotation when the pool is empty" do
    fallback_books = (1..3).map { |i| Book.create!(title: "폴백#{i}", author: "작가", category: :recommended) }

    query = query_with_pool([])
    result = query.discovery_books

    assert_equal 3, result.size
    assert result.map(&:id).to_set.subset?(fallback_books.map(&:id).to_set)
  end

  test "discovery_books falls back when the pool candidates are entirely already-active books" do
    book = Book.create!(title: "전부활동함", author: "작가", category: :recommended)
    Report.create!(user: @student, classroom: @classroom, book: book, book_title: book.title, reviewed: true)
    fallback_book = Book.create!(title: "폴백단일", author: "작가", category: :classic)

    query = query_with_pool([ book.id ]) # candidates = pool - active_book_ids = []
    result = query.discovery_books

    assert_equal [ fallback_book.id ], result.map(&:id)
  end

  # --- more_discovery_books?: 풀 경로는 풀 크기(>6)로, 폴백 경로는 기존 동작(항상 true)으로 ---

  test "more_discovery_books? is true when the pool exceeds BOOK_LIMIT" do
    books = (1..7).map { |i| Book.create!(title: "많음#{i}", author: "작가", category: :recommended) }

    assert query_with_pool(books.map(&:id)).more_discovery_books?
  end

  test "more_discovery_books? is false when the pool is exactly BOOK_LIMIT (pool path)" do
    books = (1..6).map { |i| Book.create!(title: "딱6권#{i}", author: "작가", category: :recommended) }

    assert_not query_with_pool(books.map(&:id)).more_discovery_books?
  end

  test "more_discovery_books? is true on the fallback path regardless of candidate count (existing behavior)" do
    Book.create!(title: "폴백단일버튼", author: "작가", category: :recommended)

    assert query_with_pool([]).more_discovery_books?
  end
end
