module Books
  # Book 저장 경계의 ISBN 정규화 유틸. ISBN-13은 하이픈·공백을 제거하고 검증하며,
  # 유효한 ISBN-10은 동등한 978 ISBN-13으로 변환한다. 그 외 입력은 nil을 반환한다.
  module Isbn
    module_function

    def normalize(raw)
      value = raw.to_s.gsub(/[^0-9Xx]/, "").upcase
      case value.length
      when 10
        return nil unless valid_isbn10?(value)

        isbn13_base = "978#{value.first(9)}"
        "#{isbn13_base}#{isbn13_check_digit(isbn13_base)}"
      when 13
        valid_isbn13?(value) ? value : nil
      end
    end

    def valid_isbn10?(value)
      return false unless value.match?(/\A\d{9}[\dX]\z/)

      value.chars.each_with_index.sum do |char, index|
        digit = char == "X" ? 10 : char.to_i
        digit * (10 - index)
      end.modulo(11).zero?
    end

    def valid_isbn13?(value)
      return false unless value.match?(/\A\d{13}\z/)

      value.last.to_i == isbn13_check_digit(value.first(12))
    end

    def isbn13_check_digit(first_twelve)
      sum = first_twelve.chars.each_with_index.sum do |char, index|
        char.to_i * (index.even? ? 1 : 3)
      end
      (10 - sum.modulo(10)).modulo(10)
    end
  end
end
