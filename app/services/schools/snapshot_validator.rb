module Schools
  # NEIS 전국 초등학교 스냅샷이 전량 적재에 안전한지 검증한다. 전국 검증은 수집 중단이나
  # API 필터 오류로 수백/수천 행만 받은 파일이 정상 CSV를 덮거나 운영 학교를 대량
  # 비활성화하는 사고를 막는다. 소형 fixture는 nationwide: false로 구조 검증만 수행한다.
  class SnapshotValidator
    class InvalidSnapshot < StandardError; end

    EXPECTED_OFFICE_CODES = %w[
      B10 C10 D10 E10 F10 G10 H10 I10 J10 K10 M10 N10 P10 Q10 R10 S10 T10
    ].freeze
    MINIMUM_NATIONWIDE_COUNT = 5_000

    def initialize(rows)
      @rows = Array(rows)
    end

    def validate!(nationwide: true)
      errors = structural_errors
      errors.concat(nationwide_errors) if nationwide
      raise InvalidSnapshot, errors.join("; ") if errors.any?

      true
    end

    private

    attr_reader :rows

    def structural_errors
      errors = []
      errors << "학교 데이터가 비어 있습니다" if rows.empty?

      missing_code = rows.count { |row| value(row, :neis_code).blank? }
      missing_name = rows.count { |row| value(row, :name).blank? }
      errors << "NEIS 코드가 없는 행 #{missing_code}개" if missing_code.positive?
      errors << "학교명이 없는 행 #{missing_name}개" if missing_name.positive?

      codes = rows.filter_map { |row| value(row, :neis_code).presence }
      duplicate_count = codes.size - codes.uniq.size
      errors << "중복 NEIS 코드 #{duplicate_count}개" if duplicate_count.positive?
      errors
    end

    def nationwide_errors
      errors = []
      if rows.size < MINIMUM_NATIONWIDE_COUNT
        errors << "전국 초등학교 수가 비정상적으로 적습니다(#{rows.size} < #{MINIMUM_NATIONWIDE_COUNT})"
      end

      office_codes = rows.filter_map { |row| value(row, :office_code).presence }.uniq
      missing_offices = EXPECTED_OFFICE_CODES - office_codes
      errors << "누락 시도교육청 코드: #{missing_offices.join(', ')}" if missing_offices.any?
      errors
    end

    def value(row, key)
      row[key] || row[key.to_s]
    end
  end
end
