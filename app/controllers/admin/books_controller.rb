# 전역 도서 카탈로그 CRUD(P7.3). 권장도서·고전 관리.
class Admin::BooksController < Admin::BaseController
  before_action :set_book, only: [ :show, :edit, :update, :destroy ]

  PER_PAGE = 50

  def index
    scope = Book.order(:title)
    scope = scope.where("title LIKE ?", "%#{Book.sanitize_sql_like(params[:q])}%") if params[:q].present?
    @page, @has_next_page, @books = paginate(scope)
  end

  def show
  end

  def new
    @book = Book.new
  end

  def create
    @book = Book.new(book_params)

    if @book.save
      redirect_to admin_book_path(@book), notice: "‘#{@book.title}’ 도서를 등록했어요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @book.update(book_params)
      redirect_to admin_book_path(@book), notice: "도서를 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    Book.transaction do
      @book.destroy!
      audit!("admin.book_delete", target: @book)
    end
    redirect_to admin_books_path, notice: "도서를 삭제했어요."
  end

  private

  def set_book
    @book = Book.find(params[:id])
  end

  def book_params
    params.require(:book).permit(:title, :author, :publisher, :isbn, :cover_url, :summary, :grade_band, :category)
  end
end
