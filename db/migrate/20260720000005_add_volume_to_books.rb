# 도서 시리즈 별권 구분(도서 검색 "중복" 이슈, book_search_series.md). 학습만화 시리즈물
# (설민석의 삼국지 대모험 26권·마법천자문 52권 등)은 판본마다 ISBN 이 달라 각각 별개의 Book
# 행인데, 화면에서 이를 구분할 권차 정보가 없어 자동완성에 같은 제목·저자가 수십 줄 나열됐다.
#
# db/seeds/elementary_books.tsv 에 이미 존재하는 `volume` 값(예: 21·22·23)을 담을 컬럼을 추가한다.
# 단권 도서·검색 캐시(category: searched)·권차 없는 시리즈는 NULL 로 남는다(그룹핑에서 후순위·제외).
# 순수 additive — 컬럼 추가만이라 기존 8,650행·reports.book_id 링크는 그대로 보존된다.
class AddVolumeToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :volume, :integer
  end
end
