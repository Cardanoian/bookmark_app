require "test_helper"

class Books::DeduplicatorTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "중복정리학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @student = User.create!(
      school: @school, classroom: @classroom, name: "중복정리학생", password: "password"
    )
  end

  test "dry-run reports a normalized ISBN duplicate without changing rows" do
    canonical = create_legacy_book!(title: "강아지똥", author: "권정생", category: :recommended,
                                    isbn: "978-89-86621-13-6")
    duplicate = create_legacy_book!(title: "강아지똥", author: "권정생", category: :searched,
                                    isbn: "9788986621136", cover_url: "https://img/cover")

    result = Books::Deduplicator.new(apply: false, include_shadows: false).call

    assert_equal 1, result.detected_count
    assert_equal 1, result.ready_count
    assert_equal canonical.id, result.outcomes.first.group.canonical.id
    assert Book.exists?(duplicate.id)
    assert_nil canonical.reload.cover_url
  end

  test "apply merges metadata and references then deletes the duplicate idempotently" do
    canonical = create_legacy_book!(title: "강아지똥", author: "권정생", category: :recommended,
                                    isbn: "978-89-86621-13-6")
    duplicate = create_legacy_book!(title: "강아지똥", author: "글 권정생 그림 정승각", category: :searched,
                                    isbn: "9788986621136", cover_url: "https://img/cover", genre: "문학")
    report = Report.create!(
      user: @student, classroom: @classroom, book: duplicate, book_title: duplicate.title
    )
    recommendation_import = RecommendationImport.create!(
      filename: "duplicates.xlsx", file_digest: "dedup-service-digest", imported_at: Time.current, item_count: 2
    )
    recommendation_import.book_recommendations.create!(
      book: canonical, section: "어린이문학", position: 1
    )
    recommendation_import.book_recommendations.create!(
      book: duplicate, section: "어린이문학", position: 2
    )
    GamePlay.create!(user: @student, book: canonical, game_type: :quiz, played_on: Date.current)
    GamePlay.create!(user: @student, book: duplicate, game_type: :quiz, played_on: Date.current)

    result = Books::Deduplicator.new(apply: true, include_shadows: false).call

    assert_equal 1, result.merged_count
    assert_equal 1, result.deleted_count
    assert_not Book.exists?(duplicate.id)
    canonical.reload
    assert_equal "9788986621136", canonical.isbn
    assert_equal "https://img/cover", canonical.cover_url
    assert_equal "문학", canonical.genre
    assert_equal canonical.id, report.reload.book_id
    assert_equal [ canonical.id ], recommendation_import.book_recommendations.reload.pluck(:book_id)
    assert_equal 1, recommendation_import.reload.item_count
    assert_equal [ canonical.id ], GamePlay.where(user: @student).pluck(:book_id)

    rerun = Books::Deduplicator.new(apply: true, include_shadows: false).call
    assert_equal 0, rerun.detected_count
  end

  test "apply merges a high-confidence blank ISBN shadow" do
    canonical = Book.create!(
      title: "강아지똥", author: "글: 권정생 ;그림: 정승각", publisher: "길벗어린이",
      category: :recommended, isbn: "9788986621136", cover_url: "https://img/cover"
    )
    shadow = create_legacy_book!(
      title: "강아지똥", author: "권정생", publisher: "길벗어린이",
      isbn: "", category: :recommended, summary: "민들레를 피우는 이야기"
    )

    result = Books::Deduplicator.new(apply: true).call

    assert_equal 1, result.merged_count
    assert_equal :shadow, result.outcomes.first.group.kind
    assert_not Book.exists?(shadow.id)
    assert_equal "민들레를 피우는 이야기", canonical.reload.summary
  end

  test "skips a group whose system quiz content keys would collide" do
    canonical = create_legacy_book!(title: "충돌책", category: :recommended, isbn: "978-89-86621-13-6")
    duplicate = create_legacy_book!(title: "충돌책", category: :searched, isbn: "9788986621136")
    creator = User.create!(name: "시스템", password: "password", role: :superadmin)
    [ canonical, duplicate ].each do |book|
      Quiz.create!(
        title: "시스템 퀴즈", created_by: creator, book: book, scope: :global,
        origin: :system, band: :g12, content_axis: :mcq, content_version: 1
      )
    end

    result = Books::Deduplicator.new(apply: true, include_shadows: false).call

    assert_equal 1, result.skipped_count
    assert_equal "system quiz content key conflict", result.outcomes.first.reason
    assert Book.exists?(canonical.id)
    assert Book.exists?(duplicate.id)
  end

  test "normalizes an ISBN-10 to its equivalent ISBN-13" do
    assert_equal "9788986621136", Books::Deduplicator.normalize_isbn("8986621134")
    assert_nil Books::Deduplicator.normalize_isbn("8986621130")
  end
end
