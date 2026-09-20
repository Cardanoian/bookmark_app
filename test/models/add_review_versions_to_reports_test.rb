require "test_helper"
require Rails.root.join("db/migrate/20260920000002_add_review_versions_to_reports.rb")

# 제출 버전 백필 전용 테스트(BUG_FIX_PLAN §7.1). 컬럼 추가(DDL)는 스키마에 이미 반영돼 있으므로, 백필 SQL 만
# 같은 조건으로 다시 실행해 규칙을 고정한다: 초안 0/NULL · 제출된 글 1 · 그중 done+루브릭만 완료 버전 1 ·
# 대기·처리 중·실패는 예전 루브릭이 남아 있어도 완료 버전 NULL. 본문·첨삭·포인트·updated_at 은 건드리지 않는다.
class AddReviewVersionsToReportsTest < ActiveSupport::TestCase
  RUBRIC = { "content" => 4, "emotion" => 4, "life" => 4, "structure" => 4, "spelling" => 4 }.freeze

  setup do
    @school = School.create!(name: "백필초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "백필학생", password: "password", points: 70)
  end

  test "백필은 제출 여부와 첨삭 완료 여부로 버전을 채운다" do
    rows = {
      draft: legacy_report(ai_status: :done, rubric: RUBRIC), # 고쳐쓰기 초안(원본의 done·루브릭을 물려받음)
      done: legacy_report(submitted_at: 2.days.ago, ai_status: :done, rubric: RUBRIC, reviewed: true, points_awarded: 30),
      done_without_rubric: legacy_report(submitted_at: 2.days.ago, ai_status: :done, reviewed: true),
      done_with_empty_rubric: legacy_report(submitted_at: 2.days.ago, ai_status: :done, rubric: {}),
      pending_with_old_rubric: legacy_report(submitted_at: 2.days.ago, ai_status: :pending, rubric: RUBRIC),
      processing: legacy_report(submitted_at: 2.days.ago, ai_status: :processing),
      failed_with_old_rubric: legacy_report(submitted_at: 2.days.ago, ai_status: :failed, rubric: RUBRIC)
    }
    before = Report.order(:id).pluck(:id, :body, :rubric, :points_awarded, :updated_at, :reviewed)

    backfill!
    backfill! # 다시 돌려도 같다

    versions = rows.transform_values { |report| report.reload.values_at(:review_version, :completed_review_version) }
    assert_equal [ 0, nil ], versions[:draft]
    assert_equal [ 1, 1 ], versions[:done]
    assert_equal [ 1, nil ], versions[:done_without_rubric]
    assert_equal [ 1, nil ], versions[:done_with_empty_rubric]
    assert_equal [ 1, nil ], versions[:pending_with_old_rubric], "예전 루브릭이 남아 있어도 지금 결과가 완성됐다고 보지 않는다"
    assert_equal [ 1, nil ], versions[:processing]
    assert_equal [ 1, nil ], versions[:failed_with_old_rubric]

    assert rows[:done].reload.feedback_visible?, "백필 뒤에도 승인된 첨삭은 계속 보인다"
    assert_not rows[:done_without_rubric].reload.feedback_visible?
    assert_equal before, Report.order(:id).pluck(:id, :body, :rubric, :points_awarded, :updated_at, :reviewed),
                 "본문·첨삭·포인트·updated_at·승인 표시는 그대로다"
    assert_equal 70, @student.reload.points, "포인트·경험치를 다시 계산하지 않는다"
  end

  private

  # 마이그레이션 직전의 행: 버전 컬럼이 기본값(0·NULL)이다.
  def legacy_report(**attrs)
    Report.create!(user: @student, classroom: @classroom, book_title: "백필책", body: "본문", **attrs).tap do |report|
      report.update_columns(review_version: 0, completed_review_version: nil, updated_at: 3.days.ago)
    end
  end

  # up 의 백필 구간만 실행한다(add_column 은 이미 적용된 스키마와 부딪힌다).
  def backfill!
    migration = AddReviewVersionsToReports.new
    migration.define_singleton_method(:add_column) { |*| nil }
    ActiveRecord::Migration.suppress_messages { migration.up }
  end
end
