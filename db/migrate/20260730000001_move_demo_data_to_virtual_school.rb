# 체험·데모 자료를 실학교(포항원동초등학교)에서 **가상 학교 「테스트초등학교」**로 옮긴다.
#
# 왜: 체험 계정과 39학급 데모 자료가 전국 NEIS 스냅샷의 실학교에 얹혀 있었다. 그러면
#   ① 그 학교의 실제 구성원과 데모 계정이 한 학교에 섞이고,
#   ② 대회 요강이 금지하는 실학교명이 화면·제출물 경로로 새어 나갈 여지가 남는다.
# 그래서 전국 CSV 에 없는 자체 코드(9999999)의 가상 학교를 만들고 그 학교의 **모든 행**을 옮긴다.
#
# 왜 마이그레이션인가: 시드(`accounts.yml`·`demo/*.yml`)만 고치면 **이미 만들어진 행**은 그대로
# 실학교에 남고, 시더는 신원 키(학교+학년/반+이름 / 이메일)로 찾으므로 같은 계정을 새 학교에
# **하나 더** 만든다(담임이 둘이 되고 실사용 독후감이 고아가 된다). 개명 마이그레이션
# 20260727000001 과 같은 이유·같은 방식이다.
#
# 범위: `school_id` 가 실학교인 **모든 행**을 옮긴다(users·classrooms·library_*·challenges·
# audit_logs·season_scores·topics·seasons + account_merges 의 from/to). 실학교 행 자체는
# 지우지 않는다 — 전국 6,333교 목록의 정상 데이터이고 가입 학교 선택지로 계속 쓰인다.
#
# ⚠️ 학생은 **학교+학급+이름**으로 로그인하므로, 옮겨진 학생은 로그인 시 고르는 학교가
# 「테스트초등학교」(세종특별자치시교육청)로 바뀐다. 교직원은 이메일 로그인이라 영향이 없다.
#
# 멱등: 실학교에 남은 행이 없으면(이미 옮겼으면) 각 UPDATE 가 0행이라 재실행이 무해하다.
# `down` 은 반대로 되돌리며, 가상 학교에 아무 참조도 남지 않으면 그 학교 행까지 지운다.
class MoveDemoDataToVirtualSchool < ActiveRecord::Migration[8.1]
  LEGACY_NEIS_CODE  = "8761159" # 포항원동초등학교(실학교 — 행은 보존한다)
  VIRTUAL_NEIS_CODE = "9999999" # 테스트초등학교(가상 — accounts.yml sample_accounts.school 과 동일)

  VIRTUAL_SCHOOL = {
    name: "테스트초등학교",
    region: "세종특별자치시교육청",
    gu: nil, # 세종특별자치시는 단층제 — 전국 CSV 의 세종 행들도 gu 가 비어 있다
    office_code: "I10",
    address: "세종특별자치시 테스트로 1",
    active: true,
    # neis 가 아니라 manual — `schools:seed_full` 은 data_source="neis" 행만 비활성화하므로
    # 전국 스냅샷을 다시 적재해도 이 학교가 살아남는다.
    data_source: "manual"
  }.freeze

  # school_id 컬럼으로 학교를 가리키는 테이블 전부.
  SCHOOL_ID_TABLES = %w[
    users classrooms library_loans library_events challenges audit_logs season_scores topics seasons
  ].freeze

  # account_merges 만 컬럼명이 다르다(전입 전/후 학교 스냅샷).
  MERGE_COLUMNS = %w[from_school_id to_school_id].freeze

  # 데모 담임 이메일에 남은 옛 학교 약칭. 시더의 신원 키라 YAML 과 DB 를 함께 바꿔야
  # 재시드 때 담임이 둘이 되지 않는다(db/seeds/demo/sample_*.yml).
  LEGACY_EMAIL_PREFIX  = "teacher.wondong"
  VIRTUAL_EMAIL_PREFIX = "teacher.sample"

  # 학교 스코프 챌린지 제목. 시더 멱등 키가 [scope, school_id, title] 이라 제목도 함께 옮긴다.
  LEGACY_CHALLENGE_TITLE  = "원동 여름 독서 한마당"
  VIRTUAL_CHALLENGE_TITLE = "테스트 여름 독서 한마당"

  def up
    legacy = school_id(LEGACY_NEIS_CODE)
    virtual = ensure_virtual_school!
    return if virtual.nil?

    move_rows!(from: legacy, to: virtual) if legacy
    rename_emails!(LEGACY_EMAIL_PREFIX, VIRTUAL_EMAIL_PREFIX)
    rename_challenge!(LEGACY_CHALLENGE_TITLE, VIRTUAL_CHALLENGE_TITLE, school_id: virtual)
  end

  def down
    legacy = school_id(LEGACY_NEIS_CODE)
    virtual = school_id(VIRTUAL_NEIS_CODE)
    return if virtual.nil?

    rename_challenge!(VIRTUAL_CHALLENGE_TITLE, LEGACY_CHALLENGE_TITLE, school_id: virtual)
    rename_emails!(VIRTUAL_EMAIL_PREFIX, LEGACY_EMAIL_PREFIX)

    if legacy
      move_rows!(from: virtual, to: legacy)
      # 되돌린 뒤 아무도 참조하지 않으면 가상 학교 행을 지운다(참조가 남아 있으면 보존 —
      # 마이그레이션 이후에 생긴 데이터를 연쇄 삭제하지 않기 위해서다).
      execute(<<~SQL.squish) if referencing_rows(virtual).zero?
        DELETE FROM schools WHERE id = #{virtual}
      SQL
    else
      say "실학교(neis=#{LEGACY_NEIS_CODE})가 없어 되돌릴 대상이 없습니다 — 가상 학교를 그대로 둡니다."
    end
  end

  private

  def school_id(neis_code)
    select_value("SELECT id FROM schools WHERE neis_code = #{quote(neis_code)}")
  end

  # 가상 학교를 만들거나(없으면) 기존 행을 찾아 id 를 낸다. 이름·지역이 비어 있던
  # 옛 행이 있어도 규약값으로 맞춘다.
  def ensure_virtual_school!
    existing = school_id(VIRTUAL_NEIS_CODE)
    if existing
      execute(<<~SQL.squish)
        UPDATE schools SET
          name = #{quote(VIRTUAL_SCHOOL[:name])},
          region = #{quote(VIRTUAL_SCHOOL[:region])},
          office_code = #{quote(VIRTUAL_SCHOOL[:office_code])},
          address = #{quote(VIRTUAL_SCHOOL[:address])},
          active = 1,
          data_source = #{quote(VIRTUAL_SCHOOL[:data_source])},
          updated_at = CURRENT_TIMESTAMP
        WHERE id = #{existing}
      SQL
      return existing
    end

    execute(<<~SQL.squish)
      INSERT INTO schools (neis_code, name, region, gu, office_code, address, active, data_source, created_at, updated_at)
      VALUES (
        #{quote(VIRTUAL_NEIS_CODE)}, #{quote(VIRTUAL_SCHOOL[:name])}, #{quote(VIRTUAL_SCHOOL[:region])},
        NULL, #{quote(VIRTUAL_SCHOOL[:office_code])}, #{quote(VIRTUAL_SCHOOL[:address])},
        1, #{quote(VIRTUAL_SCHOOL[:data_source])}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
    SQL
    say "가상 학교 #{VIRTUAL_SCHOOL[:name]}(neis=#{VIRTUAL_NEIS_CODE})를 만들었습니다."
    school_id(VIRTUAL_NEIS_CODE)
  end

  def move_rows!(from:, to:)
    moved = SCHOOL_ID_TABLES.sum do |table|
      next 0 unless table_exists?(table)

      execute("UPDATE #{table} SET school_id = #{to} WHERE school_id = #{from}")
      count_where(table, "school_id", to)
    end

    if table_exists?("account_merges")
      MERGE_COLUMNS.each do |column|
        execute("UPDATE account_merges SET #{column} = #{to} WHERE #{column} = #{from}")
      end
    end

    say "학교 #{from} → #{to} 이전 완료(대상 테이블 #{SCHOOL_ID_TABLES.size}종, 현재 참조 #{moved}행)."
  end

  # 이메일은 UNIQUE 라 목적지 주소가 이미 있으면 충돌한다. 그 경우는 이미 옮긴 것이므로 건너뛴다.
  def rename_emails!(from_prefix, to_prefix)
    rows = select_all(<<~SQL.squish).to_a
      SELECT id, email FROM users WHERE email LIKE #{quote("#{from_prefix}%")}
    SQL
    return if rows.empty?

    renamed = rows.count do |row|
      target = row["email"].sub(from_prefix, to_prefix)
      next false if select_value("SELECT 1 FROM users WHERE email = #{quote(target)}")

      execute("UPDATE users SET email = #{quote(target)} WHERE id = #{row['id']}")
      true
    end
    say "데모 담임 이메일 #{renamed}건을 #{to_prefix}* 로 바꿨습니다."
  end

  def rename_challenge!(from_title, to_title, school_id:)
    execute(<<~SQL.squish)
      UPDATE challenges SET title = #{quote(to_title)}, updated_at = CURRENT_TIMESTAMP
      WHERE title = #{quote(from_title)} AND school_id = #{school_id}
    SQL
  end

  def referencing_rows(school)
    SCHOOL_ID_TABLES.sum { |table| table_exists?(table) ? count_where(table, "school_id", school) : 0 }
  end

  def count_where(table, column, value)
    select_value("SELECT COUNT(*) FROM #{table} WHERE #{column} = #{value}").to_i
  end

  def quote(value)
    connection.quote(value)
  end
end
