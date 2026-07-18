# 독서활동(menu_refactor 심화 §2.D.4·§5.3). 책을 먼저 고르고 독후감/게임을 선택하는 실행 허브.
# book_id 없으면 책 선택 상태, 유효한 등록 도서면 활동 선택 상태. 표현·본인전용이라 verify_authorized 스킵.
class ReadingActivitiesController < ApplicationController
  skip_after_action :verify_authorized
  before_action :require_student!

  def show
    @book = resolve_book(params[:book_id])
    return unless @book

    @recent_reports = Current.user.reports.where(book_id: @book.id).order(created_at: :desc).limit(3).to_a
    @active_missions = StudentHomeQuery.new(Current.user).active_missions
    # 이 책으로 나눈 독서 토론(책 앵커드 진입점). 경계는 policy_scope(TopicPolicy::Scope) 로 강제해
    # 타 학급/학교 토픽이 새지 않게 하고, 기능 플래그가 꺼지면 섹션을 비운다.
    @book_topics = if reading_discussion_enabled?
      policy_scope(Topic).where(book_id: @book.id).order(created_at: :desc).limit(5).to_a
    else
      []
    end
  end

  # 인근 도서관 대출 가능 섹션(Turbo Frame lazy-load 전용). resolve_book 실패 시엔 서비스를
  # 인스턴스화하지 않고 빈 프레임만 렌더한다(방어). Current.school 은 nil 가능 → 서비스가 가드.
  def nearby_libraries
    book = resolve_book(params[:book_id])
    @nearby = book && Library::NearbyAvailability.new(book: book, school: Current.school).call
    render partial: "reading_activities/nearby_libraries", locals: { nearby: @nearby }
  end

  private

  # 등록 도서(비-searched)만 허용. 없거나 searched·미존재면 nil → 책 선택 상태로 되돌린다(§4.2).
  # 다른 학생의 개인 데이터는 book_id 만으로 조회하지 않는다(활동은 Current.user 로 스코프).
  def resolve_book(book_id)
    return nil if book_id.blank?

    Book.where.not(category: Book.categories[:searched]).find_by(id: book_id)
  end

  def require_student!
    redirect_to root_path unless Current.user&.student?
  end
end
