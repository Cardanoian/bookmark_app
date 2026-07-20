require "test_helper"

# 공용 도서 자동완성 계약(WS-A) 회귀:
#   - GET /books/autocomplete = 로컬 카탈로그(비-searched)만 + id 포함, 외부 호출 0.
#   - GET /books/search = 로컬 폴백 매치에도 id 를 실어 준다(도서 연결용).
# 외부 키는 test_helper 가 공란 강제 → 두 경로 모두 로컬(DB)만 탄다(네이버 무의존).
class BooksAutocompleteTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "자동완성학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "자동완성학생", password: "password")

    @recommended = Book.create!(title: "권장 어린왕자", author: "생텍쥐페리",
                                cover_url: "http://img/prince", category: :recommended, genre: "문학")
    @by_author = Book.create!(title: "무제", author: "홍길동", category: :classic)
    @searched = Book.create!(title: "검색캐시 어린왕자", author: "익명", category: :searched)

    # 시리즈 별권 3권(같은 제목·저자, ISBN 은 자동 부여, volume 만 다름) — 접기·드릴다운 검증용.
    # 일부러 권차 순서를 뒤섞어 생성해 대표행·권 목록 정렬(권차 오름차순)을 검증한다.
    @series_title = "삼국지 대모험"
    @series_author = "스튜디오 담"
    @vol2 = Book.create!(title: @series_title, author: @series_author, category: :recommended, volume: 2)
    @vol1 = Book.create!(title: @series_title, author: @series_author, category: :recommended, volume: 1)
    @vol3 = Book.create!(title: @series_title, author: @series_author, category: :recommended, volume: 3)
    # 같은 제목·저자의 검색 캐시(searched) 그림자 — 접기·권 목록 모두에서 제외돼야 한다.
    @series_searched = Book.create!(title: @series_title, author: @series_author, category: :searched)
  end

  test "autocomplete requires login" do
    get autocomplete_books_path, params: { q: "어린" }
    assert_response :redirect
  end

  test "autocomplete returns non-searched local books with id and excludes searched" do
    login_as(@student)
    get autocomplete_books_path, params: { q: "어린" }, as: :json

    assert_response :success
    titles = response.parsed_body.map { |item| item["title"] }
    assert_includes titles, "권장 어린왕자"
    assert_not_includes titles, "검색캐시 어린왕자", "searched 캐시는 카탈로그 자동완성에서 제외돼야 한다"

    item = response.parsed_body.find { |row| row["title"] == "권장 어린왕자" }
    assert_equal @recommended.id, item["id"]
    assert_equal "생텍쥐페리", item["author"]
    # Book#upgrade_cover_url_to_https 콜백이 http→https 로 승격해 저장하므로 응답도 https.
    assert_equal "https://img/prince", item["cover_url"]
    # 자동완성 드롭다운 배지(고전 여부·장르)용 필드도 계약에 포함한다.
    assert_equal "문학", item["genre"]
    assert_equal false, item["classic"]
    # 시리즈 접기 계약: 단권은 series_count 1·volume nil, publisher/volume/series_count 가 추가됐다.
    assert_equal 1, item["series_count"]
    assert_nil item["volume"]
    assert_equal %w[id title author publisher cover_url genre classic volume series_count].sort, item.keys.sort
  end

  test "autocomplete marks classic books so the dropdown can badge them" do
    login_as(@student)
    get autocomplete_books_path, params: { q: "홍길" }, as: :json

    assert_response :success
    item = response.parsed_body.find { |row| row["id"] == @by_author.id }
    assert item, "저자 일치 도서가 응답에 있어야 한다"
    assert_equal true, item["classic"], "classic 카테고리 도서는 classic: true 로 표시돼야 한다"
  end

  test "autocomplete matches by author too" do
    login_as(@student)
    get autocomplete_books_path, params: { q: "홍길" }, as: :json

    assert_response :success
    ids = response.parsed_body.map { |item| item["id"] }
    assert_includes ids, @by_author.id, "저자명 부분 일치도 자동완성에 잡혀야 한다"
  end

  test "autocomplete returns empty array for a blank query" do
    login_as(@student)
    get autocomplete_books_path, params: { q: "  " }, as: :json

    assert_response :success
    assert_equal [], response.parsed_body
  end

  test "search local fallback includes the local book id" do
    login_as(@student)
    get search_books_path, params: { q: "권장 어린왕자" }, as: :json

    assert_response :success
    match = response.parsed_body.find { |row| row["title"] == "권장 어린왕자" }
    assert match, "로컬 폴백이 제목 일치 도서를 반환해야 한다"
    assert_equal @recommended.id, match["id"], "search 응답도 로컬 Book PK(id)를 포함해야 한다"
  end

  # ── 시리즈 접기(book_search_series.md) ──────────────────────────────────────
  test "autocomplete folds a series into one representative row with series_count" do
    login_as(@student)
    get autocomplete_books_path, params: { q: "삼국지" }, as: :json

    assert_response :success
    series_rows = response.parsed_body.select { |row| row["title"] == @series_title }
    assert_equal 1, series_rows.size, "같은 제목·저자의 별권 3권은 대표 1행으로 접혀야 한다"

    row = series_rows.first
    assert_equal 3, row["series_count"], "series_count 는 검색 캐시를 뺀 실제 권수(3)여야 한다"
    assert_equal 1, row["volume"], "대표행은 권차가 가장 낮은 권(1권)이어야 한다"
    assert_equal @vol1.id, row["id"], "대표행 id 는 1권의 id 여야 한다"
    assert_equal @series_author, row["author"]
  end

  test "volumes endpoint returns every volume of a series in volume order, excluding searched" do
    login_as(@student)
    get volumes_books_path, params: { title: @series_title, author: @series_author }, as: :json

    assert_response :success
    assert_equal [ 1, 2, 3 ], response.parsed_body.map { |row| row["volume"] },
                 "권 목록은 권차 오름차순이어야 한다(생성 순서와 무관)"
    assert_equal [ @vol1.id, @vol2.id, @vol3.id ], response.parsed_body.map { |row| row["id"] }
    assert_not_includes response.parsed_body.map { |row| row["id"] }, @series_searched.id,
                        "검색 캐시(searched) 그림자는 권 목록에서 제외돼야 한다"
  end

  test "volumes endpoint returns empty for a blank title" do
    login_as(@student)
    get volumes_books_path, params: { title: "  " }, as: :json

    assert_response :success
    assert_equal [], response.parsed_body
  end

  test "volumes endpoint requires login" do
    get volumes_books_path, params: { title: @series_title, author: @series_author }
    assert_response :redirect
  end
end
