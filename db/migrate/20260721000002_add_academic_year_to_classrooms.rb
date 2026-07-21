# 학급을 "학년도"로 구분하기 위한 academic_year 컬럼 도입.
# 배경: 같은 학교의 "3학년 1반"이 2026학년도·2027학년도에 각각 별개 학급으로 존재해야 하는데,
# 기존 유니크 [school_id, grade, class_no] 는 연도별 중복 생성을 막았다. academic_year 를 유니크에
# 포함(4튜플)해 학년도별 공존을 허용한다(값 = 학년도 시작연도, 예: 2026학년도 → 2026).
#
# 순서(안전한 가역 마이그레이션): nullable 추가 → 백필 → NULL 0 가드 → NOT NULL → 유니크 인덱스 교체.
# 기존 행은 구 인덱스로 (school_id, grade, class_no) 유일하므로, 균일한 현재 학년도로 백필해도
# 4튜플 유일성이 보존된다. SQLite 는 change_column_null 을 테이블 재빌드로 처리하므로, 재빌드 후
# classrooms 를 참조하는 인바운드 FK(8개) 무결성을 PRAGMA foreign_key_check 로 검증한다.
class AddAcademicYearToClassrooms < ActiveRecord::Migration[8.1]
  OLD_INDEX = "index_classrooms_on_school_id_and_grade_and_class_no".freeze
  NEW_INDEX = "index_classrooms_on_school_year_grade_class".freeze

  def up
    add_column :classrooms, :academic_year, :integer

    year = current_academic_year
    execute("UPDATE classrooms SET academic_year = #{year} WHERE academic_year IS NULL")

    remaining = connection.select_value("SELECT COUNT(*) FROM classrooms WHERE academic_year IS NULL").to_i
    raise "academic_year 백필 실패: #{remaining}개 행이 여전히 NULL" unless remaining.zero?
    say "classrooms.academic_year 백필 완료 — 학년도 #{year} (분포: #{year_distribution})"

    change_column_null :classrooms, :academic_year, false

    remove_index :classrooms, name: OLD_INDEX
    add_index :classrooms, [ :school_id, :academic_year, :grade, :class_no ], unique: true, name: NEW_INDEX

    verify_foreign_keys!
  end

  # 주의: 같은 (학교·학년·반)을 이미 여러 학년도로 만든 뒤에는 down 이 불가하다 — 구 3튜플
  # 유니크 인덱스 재생성이 중복으로 실패한다(학년도 분화 전 롤백만 안전). up 은 항상 안전.
  def down
    remove_index :classrooms, name: NEW_INDEX
    add_index :classrooms, [ :school_id, :grade, :class_no ], unique: true, name: OLD_INDEX
    remove_column :classrooms, :academic_year
  end

  private

  # 현재 학년도(한국 KST 기준): 3월부터 새 학년도이므로 1·2월은 전년도.
  # 서버 전역 time_zone 설정에 의존하지 않도록 KST 로 명시 변환한다(Architect 지적).
  def current_academic_year
    today = Time.current.in_time_zone("Asia/Seoul").to_date
    today.month <= 2 ? today.year - 1 : today.year
  end

  def year_distribution
    connection.select_all("SELECT academic_year, COUNT(*) AS n FROM classrooms GROUP BY academic_year")
              .rows.map { |year, count| "#{year}:#{count}" }.join(", ")
  end

  # 테이블 재빌드(change_column_null) 후 인바운드 FK 무결성 확인. 위반 시 즉시 실패한다.
  def verify_foreign_keys!
    return unless connection.adapter_name.match?(/sqlite/i)

    violations = connection.select_all("PRAGMA foreign_key_check").to_a
    raise "classrooms 재빌드 후 FK 무결성 위반: #{violations.inspect}" if violations.any?
  end
end
