# 독서활동(menu_refactor 심화 §2.D.4·§5.3). 책을 먼저 고르고 독후감/게임을 선택하는 실행 허브.
# book_id 없으면 책 선택 상태, 유효한 등록 도서면 활동 선택 상태. 표현·본인전용이라 verify_authorized 스킵.
class ReadingActivitiesController < ApplicationController
  skip_after_action :verify_authorized
  before_action :require_student!

  def show
    @book = resolve_book(params[:book_id])
    return unless @book

    @recent_reports = Current.user.reports.where(book_id: @book.id).order(created_at: :desc).limit(3).to_a
    # 미션 문맥 배너는 이 책 활동이 실제로 미션 진행에 반영될 때만 노출한다. 진행 중 미션 전체가
    # 아니라 이 책이 반영되는 목표만 추려서 넘긴다(mission_context_for).
    @book_missions = mission_context_for(@book, StudentHomeQuery.new(Current.user).active_missions)
    # 가용성 게이트(Phase 4 §2b): 퀴즈·나는 누구게? 칩은 진짜 콘텐츠를 만들 수 있는 책에만 보여 준다
    # (창작 소셜인 책 소개 대결·뒷이야기는 콘텐츠 무관하게 항상 표시). 플레이 게이트(§2c)와 같은 판정.
    @quiz_available = Games::ContentProvider.game_content_available?(book: @book, content_axis: :mcq, user: Current.user)
    @whoami_available = Games::ContentProvider.game_content_available?(book: @book, content_axis: :hint_reveal, user: Current.user)
    bootstrap_book_summary(@book) # Phase 4 자가치유(§2c 우회 배선, 아래 주석 참조)
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
    # book·school 은 :warming 구독 스트림 이름용이다(워밍 잡이 끝나면 이 프레임을 교체한다).
    render partial: "reading_activities/nearby_libraries",
           locals: { nearby: @nearby, book: book, school: Current.school }
  end

  private

  # 진행 중 미션 중 이 책 활동이 반영되는 목표만 추린다. 각 원소는 { mission:, goals: }로,
  # goals 는 이 책이 실제 반영되는 목표의 진행 행만 담는다(뷰가 미달 목표를 배너 힌트로 렌더).
  # 반영 판정: 목표가 특정 도서를 지정하면(goal.books) 그 허용목록에 이 책이 있어야 하고,
  # 지정이 없으면(아무 책이나) 모든 책이 반영된다. 어느 목표에도 안 걸리면 제외 → 배너 미노출.
  # goal.books 는 active_missions 가 includes 로 프리로드해 N+1 없이 인메모리 판정한다.
  def mission_context_for(book, active_missions)
    active_missions.filter_map do |entry|
      mission = entry[:mission]
      eligible_types = mission.mission_goals.select do |goal|
        goal.books.empty? || goal.books.any? { |b| b.id == book.id }
      end.map(&:goal_type)
      next if eligible_types.empty?

      { mission: mission, goals: entry[:progress][:goals].select { |row| eligible_types.include?(row[:type]) } }
    end
  end

  # 등록 도서(비-searched)만 허용. 없거나 searched·미존재면 nil → 책 선택 상태로 되돌린다(§4.2).
  # 다른 학생의 개인 데이터는 book_id 만으로 조회하지 않는다(활동은 Current.user 로 스코프).
  def resolve_book(book_id)
    return nil if book_id.blank?

    Book.where.not(category: Book.categories[:searched]).find_by(id: book_id)
  end

  def require_student!
    redirect_to root_path unless Current.user&.student?
  end

  # 가용성 게이트 자가치유(게임 재구성 Phase 4 §1d 후속, code-review 지적사항). `ContentProvider#
  # maybe_enqueue_book_summary` 는 워밍이 도는 `resolve` 안에서만 걸리는데, 가용성 게이트
  # (`content_gate_allows?`)가 **비활성 책은 resolve 전에 리다이렉트**시켜 그 트리거에 절대
  # 도달하지 못한다 — 즉 "Claude가 알 수도 있는 무명 책"이 확인을 못 받아 영영 비활성으로
  # 고착된다(Part 1 취지 무력화). 학생이 책을 고르는 이 화면(게이트 우회 지점)에서 직접
  # Claude 확인을 큐잉해, 아는 책이면 다음부터 가용해지는 온디맨드 자가치유 경로를 확보한다.
  # 잡이 멱등이라 중복 안전(같은 책을 여러 번 봐도 최초 1회만 실질 확인), 무키면 큐잉 안 함
  # (`Ai::ClaudeClient.new.configured?` 가드 — 무의미한 큐잉 방지, 잡 자체도 무키 no-op).
  def bootstrap_book_summary(book)
    return unless book.summary.blank? && book.summary_checked_at.nil?
    return unless Ai::ClaudeClient.new.configured?

    BookSummaryJob.perform_later(book.id)
  end
end
