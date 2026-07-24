require "test_helper"

# WS-D2 — 도서 장르 오프라인 보강 잡. 분류된 이웃에서 무API 로 genre 를 채우되, 기존 genre 는
# 절대 덮어쓰지 않는다(멱등). 이웃이 없거나 book 이 없으면 조용히 no-op.
class BookEnrichmentJobTest < ActiveJob::TestCase
  test "분류된 이웃에서 공란 genre 를 추론해 채운다(무API)" do
    Book.create!(title: "해리 포터와 마법사의 돌", author: "조앤 롤링", publisher: "문학수첩", genre: "문학")
    Book.create!(title: "해리 포터와 비밀의 방", author: "조앤 롤링", publisher: "문학수첩", genre: "문학")
    Book.create!(title: "수학의 정석 기초편", author: "홍성대", publisher: "성지출판", genre: "자연과학")
    target = Book.create!(title: "해리 포터와 불의 잔", author: "조앤 롤링", publisher: "문학수첩", category: :searched)

    BookEnrichmentJob.perform_now(target.id)

    assert_equal "문학", target.reload.genre
  end

  test "이미 genre 가 있으면 덮어쓰지 않는다(멱등)" do
    Book.create!(title: "과학 실험 이야기", author: "김과학", genre: "자연과학")
    target = Book.create!(title: "과학 실험 대백과", author: "김과학", genre: "역사·지리", category: :searched)

    BookEnrichmentJob.perform_now(target.id)

    assert_equal "역사·지리", target.reload.genre
  end

  test "분류된 이웃이 없으면 아무것도 하지 않는다(무장르 유지)" do
    target = Book.create!(title: "외톨이 책", category: :searched)

    assert_nothing_raised { BookEnrichmentJob.perform_now(target.id) }
    assert_nil target.reload.genre
  end

  test "존재하지 않는 book_id 는 조용히 무시한다" do
    assert_nothing_raised { BookEnrichmentJob.perform_now(-1) }
  end
end
