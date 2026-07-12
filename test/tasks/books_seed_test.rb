require "test_helper"
require "rake"

# books:seed 검증(계획 §3·§5). 밴드별 큐레이션 카탈로그가 표준 밴드 라벨로 멱등 적재되는지 확인.
class BooksSeedTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("books:seed")
  end

  def run_seed!
    Rake::Task["books:seed"].reenable
    capture_io { Rake::Task["books:seed"].invoke }
  end

  test "seeds a graded catalog across all three standard bands" do
    run_seed!

    Book::GRADE_BANDS.each do |band|
      assert_operator Book.where(grade_band: band).count, :>, 0, "#{band} 밴드 도서가 있어야 한다"
    end
  end

  test "every catalog book uses a standard grade band label" do
    run_seed!

    Book.where(category: [ :recommended, :classic ]).find_each do |book|
      assert_includes Book::GRADE_BANDS, book.grade_band, "#{book.title} 의 grade_band 는 표준 라벨이어야 한다"
    end
  end

  test "seeds both recommended and classic categories" do
    run_seed!

    assert_operator Book.recommended.count, :>, 0
    assert_operator Book.classic.count, :>, 0
  end

  test "meaningfully expands the catalog beyond the previous single-band 34" do
    run_seed!

    assert_operator Book.count, :>, 34, "다밴드 확장으로 이전 34권보다 늘어야 한다"
  end

  test "seeding is idempotent (find_or_initialize by title+author)" do
    run_seed!
    count = Book.count
    run_seed!

    assert_equal count, Book.count, "재실행해도 중복되지 않는다"
  end
end
