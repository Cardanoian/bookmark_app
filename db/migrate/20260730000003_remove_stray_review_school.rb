# 수기 검토 중 만들어져 남은 학교 행 정리(데이터 전용).
#
# 개발·운영 DB 양쪽에 `리뷰검증초_8949`(neis_code NULL · region NULL · data_source manual ·
# active true, 2026-07-21 생성) 한 건이 남아 있었다. 코드·시드 어디에도 이 이름을 만드는 곳이
# 없고(리포 전역 grep 0건) 참조도 0건이라, 수기 확인 과정에서 만들어진 잔여 데이터다.
#
# 왜 지우는가: `School.form_regions`·학교 선택 피커·학교 랭킹이 **active 학교를 그대로 노출**하므로
# 검증용 행이 가입 화면과 랭킹에 섞여 보인다(neis_code 가 NULL 이라 시드·스냅샷이 손대지도 못한다).
#
# 안전장치: 이름 패턴만으로 지우지 않는다. **참조가 0건인 행만** 지우고, 한 건이라도 붙어 있으면
# 건너뛰며 로그를 남긴다 — 실수로 학급·학생이 딸린 학교를 연쇄 삭제(`dependent: :destroy`)하지
# 않기 위해서다. 그래서 재실행해도 안전하고(대상 0건), 다른 DB 에서는 조용히 no-op 한다.
class RemoveStrayReviewSchool < ActiveRecord::Migration[8.1]
  NAME_PATTERN = "리뷰검증%"

  # school_id 로 학교를 가리키는 테이블 전부(20260730000001/2 와 같은 집합).
  SCHOOL_ID_TABLES = %w[
    users classrooms library_loans library_events challenges audit_logs season_scores topics seasons
  ].freeze

  def up
    rows = select_all(<<~SQL.squish).to_a
      SELECT id, name FROM schools
      WHERE name LIKE #{quote(NAME_PATTERN)} AND neis_code IS NULL
    SQL
    return if rows.empty?

    rows.each do |row|
      referencing = referencing_rows(row["id"])
      if referencing.positive?
        say "#{row['name']}(id=#{row['id']}) 참조 #{referencing}건 — 건너뜁니다."
        next
      end

      execute("DELETE FROM schools WHERE id = #{row['id']}")
      say "검증용 학교 행 #{row['name']}(id=#{row['id']})을 삭제했습니다."
    end
  end

  # 되돌리지 않는다 — 되살릴 가치가 없는 잔여 데이터이고, 원본 속성(전부 NULL)도 복원할 의미가
  # 없다. raise 하지 않는 이유는 이 마이그레이션 때문에 뒤 단계 롤백이 막히지 않게 하기 위해서다.
  def down
    say "검증용 학교 행은 복원하지 않습니다(되살릴 가치가 없는 잔여 데이터)."
  end

  private

  def referencing_rows(school_id)
    count = SCHOOL_ID_TABLES.sum do |table|
      next 0 unless table_exists?(table)

      select_value("SELECT COUNT(*) FROM #{table} WHERE school_id = #{school_id}").to_i
    end
    return count unless table_exists?("account_merges")

    count + select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM account_merges
      WHERE from_school_id = #{school_id} OR to_school_id = #{school_id}
    SQL
  end

  def quote(value)
    connection.quote(value)
  end
end
