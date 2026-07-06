# 도서 카탈로그·검색(P5.1/P5.2). index=카탈로그(카테고리 필터), show=상세,
# search=Kakao/Naver 자동완성 JSON(무키/실패 시 로컬 캐시 폴백).
class BooksController < ApplicationController
  def index
    authorize :book, :index?
    @category = params[:category].presence_in(Book.categories.keys)
    scope = Book.all
    scope = scope.where(category: @category) if @category
    @books = scope.order(:title)
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
end
