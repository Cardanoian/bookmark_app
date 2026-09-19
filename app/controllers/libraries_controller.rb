# 내 서재(menu_refactor 심화 §2.D.4). 현재 학생의 책별 활동 포트폴리오(읽기 전용).
# 표현·본인전용(StudentLibraryQuery 가 Current.user 로 스코프)이라 verify_authorized 를 스킵한다.
class LibrariesController < ApplicationController
  skip_after_action :verify_authorized
  before_action :require_student!

  # 활동 종류 필터 칩 라벨. 게임 이름은 게임 카탈로그가 단일 진실이다.
  KIND_LABELS = {
    "reports" => "독후감",
    "forum" => "토론",
    "contributions" => "내가 낸 문제"
  }.merge(Games::BaseController::CATALOG.transform_values { |meta| meta[:name] }).freeze

  # kind 필터: nil(전체) | StudentLibraryQuery::KINDS(독후감·게임 4종·토론·내가 낸 문제). 모르는 값은 전체.
  def show
    forum = reading_discussion_enabled?
    query = StudentLibraryQuery.new(Current.user, kind: params[:kind].presence, forum: forum)
    @kind = query.kind
    # 독서 토론이 꺼진 학급에는 '토론' 칩을 두지 않는다(집계도 하지 않는다).
    @filters = [ [ nil, "전체" ] ] + StudentLibraryQuery::KINDS.filter_map do |kind|
      [ kind, KIND_LABELS.fetch(kind) ] unless kind == "forum" && !forum
    end
    @entries = query.entries
    @legacy_groups = query.legacy_report_groups
    @game_catalog = Games::BaseController::CATALOG
  end

  private

  def require_student!
    redirect_to root_path unless Current.user&.student?
  end
end
