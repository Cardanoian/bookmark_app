class BackfillSquishedBookTitles < ActiveRecord::Migration[8.1]
  # 레거시 자유입력 book_title 의 앞뒤·중복 공백을 정리(squish)해 index book_title 필터가
  # 정규화 값 하나로 조회되게 한다. 데이터 전용·멱등(테이블 구조 변경 없음). update_columns 로
  # 콜백·타임스탬프를 우회하고, 이미 정규화된 값은 건너뛰어 재실행해도 안전하다.
  def up
    Report.reset_column_information
    Report.where.not(book_title: [ nil, "" ]).find_each do |r|
      squished = r.book_title.to_s.squish.presence
      r.update_columns(book_title: squished) if squished != r.book_title
    end
  end

  def down
  end
end
