class RemoveLegacySampleSchools < ActiveRecord::Migration[8.1]
  # 전국 NEIS 스냅샷 도입 전에 사용한 합성 학교 코드. 이름 앞의 지역 접두어만 제거하면
  # 실제 대표 학교가 명확한 경우에는 연결 데이터를 공식 NEIS 행으로 옮긴다.
  SAMPLE_TO_OFFICIAL_CODE = {
    "7010001" => "7132080", # 서울강남초등학교 → 서울강남초등학교
    "7020001" => "7211083", # 부산해운대초등학교 → 해운대초등학교
    "7030001" => "7251053", # 대구수성초등학교 → 대구수성초등학교
    "7040001" => "7341048", # 인천연수초등학교 → 인천연수초등학교
    "7050001" => "7392109", # 광주서석초등학교 → 광주서석초등학교
    "7060001" => "7451122", # 대전유성초등학교 → 유성초등학교
    "7070001" => "7501061", # 울산남부초등학교 → 울산남부초등학교
    "7080001" => "9300087", # 세종한솔초등학교 → 한솔초등학교
    "7090001" => "7541092", # 경기수원초등학교 → 수원초등학교
    "7100001" => "7811049", # 강원춘천초등학교 → 춘천초등학교
    "7120001" => "8151069", # 충남천안초등학교 → 천안초등학교
    "7130001" => "8332185", # 전북전주초등학교 → 전주초등학교
    "7150001" => "8761159", # 포항원동초등학교 → 포항원동초등학교
    "7160001" => "9022101", # 경남창원초등학교 → 창원초등학교
    "7170001" => "9296040"  # 제주제주북초등학교 → 제주북초등학교
  }.freeze

  LEGACY_CODES = %w[
    7010001 7020001 7030001 7040001 7050001 7060001
    7070001 7080001 7090001 7100001 7110001 7120001
    7130001 7140001 7150001 7160001 7170001
  ].freeze
  CLASSROOM_REFERENCES = %w[book_intros missions quizzes reports topics users].freeze
  SCHOOL_REFERENCES = %w[challenges library_events library_loans seasons topics users].freeze

  def up
    LEGACY_CODES.each do |legacy_code|
      legacy_id = select_value(<<~SQL)&.to_i
        SELECT id FROM schools WHERE neis_code = #{quote(legacy_code)} LIMIT 1
      SQL
      next unless legacy_id

      official_code = SAMPLE_TO_OFFICIAL_CODE[legacy_code]
      official_id = official_code && select_value(<<~SQL)&.to_i
        SELECT id FROM schools WHERE neis_code = #{quote(official_code)} LIMIT 1
      SQL

      if official_id
        merge_school!(legacy_id, official_id)
      elsif unreferenced_school?(legacy_id)
        execute("DELETE FROM schools WHERE id = #{legacy_id}")
      else
        # 청주·순천 합성명처럼 대응 학교를 단정할 수 없고 연결 데이터가 있다면 삭제하지 않는다.
        # 랭킹/학교 선택에서는 제외되며 운영자가 올바른 학교를 확인한 뒤 이관할 수 있다.
        execute(<<~SQL)
          UPDATE schools
          SET active = 0, data_source = 'sample'
          WHERE id = #{legacy_id}
        SQL
      end
    end
  end

  def down
    # 합성 학교 행을 복원하면 같은 문제가 재발하고, 삭제 전 연결 상태도 완전히 재현할 수 없다.
  end

  private

  def merge_school!(legacy_id, official_id)
    select_all(<<~SQL).each do |classroom|
      SELECT id, grade, class_no FROM classrooms WHERE school_id = #{legacy_id}
    SQL
      replacement_id = select_value(<<~SQL)&.to_i
        SELECT id
        FROM classrooms
        WHERE school_id = #{official_id}
          AND grade IS #{sql_value(classroom["grade"])}
          AND class_no IS #{sql_value(classroom["class_no"])}
        LIMIT 1
      SQL

      if replacement_id
        CLASSROOM_REFERENCES.each do |table|
          update_reference(table, "classroom_id", classroom["id"].to_i, replacement_id)
        end
        execute("DELETE FROM classrooms WHERE id = #{classroom['id'].to_i}")
      else
        update_reference("classrooms", "school_id", classroom["id"].to_i, official_id, key: "id")
      end
    end

    SCHOOL_REFERENCES.each do |table|
      update_reference(table, "school_id", legacy_id, official_id)
    end
    execute("DELETE FROM schools WHERE id = #{legacy_id}")
  end

  def update_reference(table, column, old_id, new_id, key: column)
    return unless table_exists?(table) && column_exists?(table, column)

    execute(<<~SQL)
      UPDATE #{quote_table_name(table)}
      SET #{quote_column_name(column)} = #{new_id}
      WHERE #{quote_column_name(key)} = #{old_id}
    SQL
  end

  def unreferenced_school?(school_id)
    tables = [ "classrooms", *SCHOOL_REFERENCES ].select do |table|
      table_exists?(table) && column_exists?(table, "school_id")
    end

    tables.all? do |table|
      select_value(<<~SQL).to_i.zero?
        SELECT COUNT(*) FROM #{quote_table_name(table)} WHERE school_id = #{school_id}
      SQL
    end
  end

  def sql_value(value)
    value.nil? ? "NULL" : quote(value)
  end
end
