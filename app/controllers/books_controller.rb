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

  private

  # 카탈로그에서 둘러볼 수 있는 카테고리(검색 캐시 searched 제외).
  def catalog_categories
    Book.categories.keys - %w[searched]
  end
end
