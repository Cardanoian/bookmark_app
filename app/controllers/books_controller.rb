# 도서 카탈로그·검색(P5.1/P5.2). index=카탈로그(카테고리 필터), show=상세,
# search=네이버 도서검색 자동완성 JSON(무키/실패 시 로컬 캐시 폴백).
class BooksController < ApplicationController
  PER_PAGE = 24

  # 카탈로그 목록을 페이지네이션한다(#2). 검색 upsert 캐시(category: searched)는
  # 무한 증가원이라 카탈로그 목록에서 제외한다(별도 로컬 검색 폴백에서만 쓰임).
  def index
    authorize :book, :index?
    @page = [ params[:page].to_i, 1 ].max
    @category = params[:category].presence_in(catalog_categories)
    scope = Book.where.not(category: :searched)
    scope = scope.where(category: @category) if @category
    records = scope.order(:title)
                   .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @has_next_page = records.size > PER_PAGE
    @books = records.first(PER_PAGE)
  end

  def show
    @book = Book.find(params[:id])
    authorize :book, :show?
    @reports = @book.reports.where(shared: true).includes(:user).order(created_at: :desc)
  end

  # 자동완성용 정규화 배열(JSON). 오프라인/무키에서도 로컬 폴백으로 응답.
  def search
    authorize :book, :search?
    @results = Books::SearchService.new.call(params[:q])
    render json: @results
  end

  # 검색 버튼(원격) 전용 도서 검색(JSON). 네이버 결과를 반환하며 서버가 정규화 메타를
  # isbn 키로 짧게 캐시한다(제출 시 SearchService#register 가 재사용). 타이핑 자동완성과
  # 분리 — 무키/실패 시 [](로컬 폴백 없음). 도서 폼의 "검색" 버튼에만 배정한다.
  def remote_search
    authorize :book, :search?
    render json: Books::SearchService.new.remote_search(params[:q])
  end

  # 로컬 카탈로그 자동완성(외부 호출 0). 검색 캐시(searched)는 제외해 카탈로그 도서만
  # 제안한다 — 독후감·게임 폼의 도서 연결용 공용 자동완성 계약(id 포함).
  #
  # 시리즈 접기(book_search_series.md): 같은 제목·저자의 별권을 대표 1행으로 접고 series_count 를
  # 실어, 학습만화 시리즈물(설민석의 삼국지 26권 등)이 드롭다운을 통째로 점유하지 않게 한다.
  # series_count > 1 이면 프런트가 배지·권 선택 2단계(#volumes)로 분기하고, 단권(=1)은 즉시 선택된다.
  def autocomplete
    authorize :book, :search?
    term = params[:q].to_s.strip
    return render(json: []) if term.blank?

    render json: Book.autocomplete_grouped(term).map { |book|
      { id: book.id, title: book.title.to_s, author: book.author.to_s, publisher: book.publisher.to_s,
        cover_url: book.cover_url.to_s, genre: book.genre.to_s, classic: book.classic?,
        volume: book.volume, series_count: book["series_count"].to_i }
    }
  end

  # 시리즈 권 목록(로컬 카탈로그 전용, 외부 호출 0). 자동완성 드릴다운(시리즈→권 선택 2단계) 전용
  # 엔드포인트 — 첫 자동완성 응답의 title·author 를 그대로 받아 그 시리즈의 전 권을 권차 순으로
  # 반환한다. 26권 페이로드를 첫 응답에 싣지 않고 시리즈를 고른 순간에만 온디맨드로 조회한다.
  def volumes
    authorize :book, :search?
    title = params[:title].to_s.strip
    return render(json: []) if title.blank?

    render json: Book.series_volumes(title, params[:author]).map { |book|
      { id: book.id, title: book.title.to_s, author: book.author.to_s, publisher: book.publisher.to_s,
        cover_url: book.cover_url.to_s, genre: book.genre.to_s, classic: book.classic?,
        volume: book.volume }
    }
  end

  private

  # 카탈로그에서 둘러볼 수 있는 카테고리(검색 캐시 searched 제외).
  def catalog_categories
    Book.categories.keys - %w[searched]
  end
end
