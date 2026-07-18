class AddGenreToBooks < ActiveRecord::Migration[8.1]
  # 도서 장르(10개 대분류 문자열). 네이버 등록 도서는 비동기 BookEnrichmentJob 이
  # Books::GenreInference(무API 규칙/이웃 추론)로 채운다. 미분류는 null.
  def change
    add_column :books, :genre, :string
  end
end
