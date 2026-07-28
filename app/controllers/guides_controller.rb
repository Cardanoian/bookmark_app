# 사용방법 안내(학생 도움말). 상단 학생 메뉴 "사용방법"의 목적지로, 로그인·독후감·첨삭·게임·
# 몬스터로 이어지는 앱 전체 흐름을 한 화면에서 훑게 한다(manual/01-학생-매뉴얼.md 의 화면판).
#
# 개인 데이터를 전혀 읽지 않는 **정적 표현 화면**이라 verify_authorized 를 스킵하고 학생 게이트만
# 둔다(libraries·reading_activities 관례). 화면에 적는 수치·명칭은 하드코딩하지 않고 도메인 상수
# (5축·등급 포인트·게임 카탈로그·퀴즈 정답 포인트)에서 파생해, 규칙이 바뀌면 안내도 함께 바뀐다.
class GuidesController < ApplicationController
  skip_after_action :verify_authorized
  before_action :require_student!

  # 게임 4종의 학생 눈높이 한 줄 설명. 이름·아이콘은 카탈로그 단일 진실
  # (`Games::BaseController::CATALOG`)에서 가져오므로 여기엔 설명만 둔다.
  GAME_DESCRIPTIONS = {
    "quiz" => "책 내용을 4지선다로 풀어요.",
    "whoami" => "힌트를 하나씩 열어 보며 누구인지 알아맞혀요.",
    "book" => "책 소개를 쓰고 친구들과 투표로 겨뤄요.",
    "sequel" => "책 뒤에 이어질 이야기를 상상해서 써요."
  }.freeze

  def show
    @axes = rubric_axes
    @level_points = ReadingDomain::LEVEL_POINTS
    @quiz_points = Games::QuestionScorer::POINTS_PER_CORRECT
    @games = Games::BaseController::CATALOG.map do |key, meta|
      { name: meta[:name], icon: meta[:icon], description: GAME_DESCRIPTIONS[key] }
    end
  end

  private

  # 5축 라벨 + 학년군 눈높이 설명. 밴드는 age-safe 규칙(guided_band_for — 학년 미상은 최저 밴드)을
  # 따라 첨삭 안내가 실제 학생 학년보다 어려운 문장으로 보이지 않게 한다.
  def rubric_axes
    band = ReadingDomain.guided_band_for(Current.user.classroom&.grade)
    meanings = ReadingDomain::AXIS_MEANINGS_BY_BAND.fetch(band, ReadingDomain::AXIS_MEANINGS_BY_BAND[:g56])
    ReadingDomain::RUBRIC_AXES.map do |axis|
      { label: ReadingDomain::AXIS_LABELS.fetch(axis), meaning: meanings[axis] }
    end
  end

  def require_student!
    redirect_to root_path unless Current.user&.student?
  end
end
