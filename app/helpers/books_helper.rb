module BooksHelper
  # 장르 추론(Books::GenreInference)이 분류 실패 시 남기는 값. 표시에서 숨긴다.
  UNCLASSIFIED_GENRE = "미분류".freeze

  # 화면에 표시할 장르 라벨(공란·미분류는 nil). genre 컬럼은 이미 한국어 라벨
  # (문학·자연과학·역사·지리 등 10종)이라 별도 매핑 없이 그대로 쓴다.
  def book_genre_label(book)
    label = book&.genre.to_s.strip
    return if label.blank? || label == UNCLASSIFIED_GENRE

    label
  end

  # 책 카드·상세에 공통으로 붙는 메타 배지(고전 여부 + 장르).
  #   - 고전: category enum(classic) 로 판정 — 장르와 독립된 축이라 함께 노출.
  #   - 장르: book_genre_label (미분류·공란 숨김).
  # 둘 다 없으면 빈 문자열을 반환해 호출부가 그대로 삽입해도 안전하다.
  # size: :sm(좁은 카드 — badge-sm 컴팩트) | :md(기본 크기) | :lg(도서 상세 — badge-lg).
  BADGE_SIZE_CLASSES = { sm: "badge-sm", md: nil, lg: "badge-lg" }.freeze

  def book_meta_badges(book, size: :sm, wrapper_class: "mt-1")
    return "".html_safe if book.nil?

    size_class = BADGE_SIZE_CLASSES.fetch(size.to_sym, nil)
    badges = []
    badges << tag.span("고전", class: class_names("badge", size_class, "badge-yellow")) if book.classic?
    if (genre = book_genre_label(book))
      badges << tag.span(genre, class: class_names("badge", size_class, "badge-neutral"))
    end
    return "".html_safe if badges.empty?

    tag.span(safe_join(badges), class: class_names("flex flex-wrap items-center gap-1", wrapper_class))
  end
end
