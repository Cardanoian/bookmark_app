# 남은 데모 학급 자료를 **실학교 14곳 → 각각의 가상 학교**로 옮긴다(20260730000001 의 후속).
#
# 앞선 마이그레이션은 체험 계정이 사는 학교 하나(포항원동초 → 테스트초등학교)만 옮겼다. 나머지
# 15개 데모 학급은 여전히 전국 NEIS 스냅샷의 실학교 14곳에 얹혀 있었고, **학교 랭킹 화면은
# 학교명을 그대로 렌더**하므로 실학교명이 심사 화면에 노출될 수 있었다.
#
# 학교마다 1:1 로 가상 학교를 만들어(실학교 1곳 = 가상 학교 1곳) 그 학교의 **모든 행**을 옮긴다.
# 실학교 행 자체는 지우지 않는다 — 전국 6,333교 목록의 정상 데이터이자 가입 학교 선택지다.
#
# 가상 학교 규약은 `db/seeds/demo/schools.yml` 과 동일하다: 전국 CSV 에 없는 자리표 코드 ·
# `data_source: manual`(schools:seed_full 이 비활성화하지 않음) · 세종특별자치시교육청 · gu 없음
# (세종 단층제라 전국 CSV 의 세종 행들도 gu 가 비어 있어 학교 선택 피커와 어긋나지 않는다) ·
# 이름은 전국 CSV 실학교명과 겹치지 않는 것만 골랐다(학교 랭킹에 그대로 노출되므로).
#
# 담임 이메일(`teacher.<옛 학교 약칭>@chaekgalpi.demo`)도 함께 바꾼다 — DemoSeeder 의 신원 키라
# YAML 만 고치면 재시드 때 담임이 둘이 된다(20260730000001 과 같은 이유).
#
# 멱등: 실학교에 남은 행이 없으면 각 UPDATE 가 0행이라 재실행이 무해하다. `down` 은 반대로
# 되돌리며, 가상 학교에 아무 참조도 남지 않으면 그 학교 행까지 지운다.
class MoveRemainingDemoSchools < ActiveRecord::Migration[8.1]
  REGION = "세종특별자치시교육청"
  OFFICE_CODE = "I10"

  # 실학교 neis → 가상 학교. 효자초는 학급이 2개라 데모 파일이 2개지만 학교는 하나다.
  SCHOOLS = [
    { legacy: "7491095", code: "9999985", name: "나린초등학교", address: "세종특별자치시 테스트로 2" }, # 구 남외초등학교
    { legacy: "7501044", code: "9999986", name: "별하초등학교", address: "세종특별자치시 테스트로 3" }, # 구 동백초등학교
    { legacy: "7501053", code: "9999987", name: "이든초등학교", address: "세종특별자치시 테스트로 4" }, # 구 신정초등학교
    { legacy: "8761121", code: "9999988", name: "하람초등학교", address: "세종특별자치시 테스트로 5" }, # 구 대이초등학교
    { legacy: "8761122", code: "9999989", name: "초아초등학교", address: "세종특별자치시 테스트로 6" }, # 구 대잠초등학교
    { legacy: "8761127", code: "9999990", name: "노을초등학교", address: "세종특별자치시 테스트로 7" }, # 구 문덕초등학교
    { legacy: "8761141", code: "9999991", name: "단비초등학교", address: "세종특별자치시 테스트로 8" }, # 구 유강초등학교
    { legacy: "8761168", code: "9999992", name: "온누리초등학교", address: "세종특별자치시 테스트로 9" }, # 구 효자초등학교
    { legacy: "8771070", code: "9999993", name: "하온초등학교", address: "세종특별자치시 테스트로 10" }, # 구 경주초등학교
    { legacy: "8801092", code: "9999994", name: "별빛초등학교", address: "세종특별자치시 테스트로 11" }, # 구 구미왕산초등학교
    { legacy: "9022015", code: "9999995", name: "나온초등학교", address: "세종특별자치시 테스트로 12" }, # 구 광려초등학교
    { legacy: "9051008", code: "9999996", name: "햇살초등학교", address: "세종특별자치시 테스트로 13" }, # 구 가좌초등학교
    { legacy: "9091006", code: "9999997", name: "아린초등학교", address: "세종특별자치시 테스트로 14" }, # 구 경운초등학교
    { legacy: "9091046", code: "9999998", name: "물빛초등학교", address: "세종특별자치시 테스트로 15" } # 구 율하초등학교
  ].freeze

  EMAIL_RENAMES = {
    "teacher.changwon5_2" => "teacher.naon5_2",
    "teacher.gimhae4_1" => "teacher.arin4_1",
    "teacher.gumi6_3" => "teacher.byeolbit6_3",
    "teacher.gyeongju3_2" => "teacher.haon3_2",
    "teacher.hyoja1" => "teacher.onnuri2_1",
    "teacher.hyoja2" => "teacher.onnuri1_4",
    "teacher.jinju2_3" => "teacher.haetsal2_3",
    "teacher.mundeok" => "teacher.noeul3_1",
    "teacher.pohang1_2" => "teacher.haram1_2",
    "teacher.pohang6_4" => "teacher.choa6_4",
    "teacher.ulsan1_3" => "teacher.narin1_3",
    "teacher.ulsan3_1" => "teacher.byeolha3_1",
    "teacher.ulsan5_1" => "teacher.ideun5_1",
    "teacher.yugang" => "teacher.danbi5_3",
    "teacher.yulha" => "teacher.mulbit4_2"
  }.freeze

  SCHOOL_ID_TABLES = %w[
    users classrooms library_loans library_events challenges audit_logs season_scores topics seasons
  ].freeze

  MERGE_COLUMNS = %w[from_school_id to_school_id].freeze

  def up
    SCHOOLS.each do |entry|
      virtual = ensure_school!(entry)
      legacy = school_id(entry[:legacy])
      move_rows!(from: legacy, to: virtual) if legacy && virtual
    end
    rename_emails!(EMAIL_RENAMES)
  end

  def down
    rename_emails!(EMAIL_RENAMES.invert)
    SCHOOLS.each do |entry|
      virtual = school_id(entry[:code])
      legacy = school_id(entry[:legacy])
      next if virtual.nil?

      if legacy
        move_rows!(from: virtual, to: legacy)
        execute("DELETE FROM schools WHERE id = #{virtual}") if referencing_rows(virtual).zero?
      else
        say "실학교(neis=#{entry[:legacy]}) 없음 — #{entry[:name]} 은 그대로 둡니다."
      end
    end
  end

  private

  def school_id(neis_code)
    select_value("SELECT id FROM schools WHERE neis_code = #{quote(neis_code)}")
  end

  def ensure_school!(entry)
    existing = school_id(entry[:code])
    if existing
      execute(<<~SQL.squish)
        UPDATE schools SET
          name = #{quote(entry[:name])}, region = #{quote(REGION)}, gu = NULL,
          office_code = #{quote(OFFICE_CODE)}, address = #{quote(entry[:address])},
          active = 1, data_source = 'manual', updated_at = CURRENT_TIMESTAMP
        WHERE id = #{existing}
      SQL
      return existing
    end

    execute(<<~SQL.squish)
      INSERT INTO schools (neis_code, name, region, gu, office_code, address, active, data_source, created_at, updated_at)
      VALUES (#{quote(entry[:code])}, #{quote(entry[:name])}, #{quote(REGION)}, NULL,
              #{quote(OFFICE_CODE)}, #{quote(entry[:address])}, 1, 'manual', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    say "가상 학교 #{entry[:name]}(neis=#{entry[:code]})를 만들었습니다."
    school_id(entry[:code])
  end

  def move_rows!(from:, to:)
    SCHOOL_ID_TABLES.each do |table|
      execute("UPDATE #{table} SET school_id = #{to} WHERE school_id = #{from}") if table_exists?(table)
    end
    return unless table_exists?("account_merges")

    MERGE_COLUMNS.each do |column|
      execute("UPDATE account_merges SET #{column} = #{to} WHERE #{column} = #{from}")
    end
  end

  # 이메일은 UNIQUE 라 목적지 주소가 이미 있으면 건너뛴다(이미 옮긴 상태).
  # 짧은 접두가 긴 접두를 먹지 않도록 **정확 일치**(`<접두>@chaekgalpi.demo`)로만 바꾼다.
  def rename_emails!(mapping)
    renamed = mapping.count do |from, to|
      old_email = "#{from}@chaekgalpi.demo"
      new_email = "#{to}@chaekgalpi.demo"
      next false unless select_value("SELECT 1 FROM users WHERE email = #{quote(old_email)}")
      next false if select_value("SELECT 1 FROM users WHERE email = #{quote(new_email)}")

      execute("UPDATE users SET email = #{quote(new_email)} WHERE email = #{quote(old_email)}")
      true
    end
    say "데모 담임 이메일 #{renamed}건을 바꿨습니다." if renamed.positive?
  end

  def referencing_rows(school)
    SCHOOL_ID_TABLES.sum do |table|
      next 0 unless table_exists?(table)

      select_value("SELECT COUNT(*) FROM #{table} WHERE school_id = #{school}").to_i
    end
  end

  def quote(value)
    connection.quote(value)
  end
end
