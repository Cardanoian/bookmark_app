# 이 책의 내 기록(내 서재 책 제목의 목적지). 현재 학생이 그 책으로 한 활동 — 독후감·게임 완료·뒷이야기·
# 책 소개·토론 글·낸 문제 — 을 한 화면에 모은다. 조회는 전부 StudentBookRecordsQuery 가 Current.user 로
# 좁히는 본인 전용 표현 화면이라(책 id 만으로는 남의 데이터에 닿지 않는다) libraries 관례대로
# verify_authorized 를 스킵한다.
class LibraryBooksController < ApplicationController
  skip_after_action :verify_authorized
  before_action :require_student!

  def show
    @book = Book.find(params[:id])
    @records = StudentBookRecordsQuery.new(Current.user, @book, forum: reading_discussion_enabled?)
    # 게임 완료 칩의 이름·아이콘(guides_controller 와 같은 단일 진실).
    @game_catalog = Games::BaseController::CATALOG
  end

  private

  def require_student!
    redirect_to root_path unless Current.user&.student?
  end
end
