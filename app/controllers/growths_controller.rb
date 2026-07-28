# 나의 성장(P1-8). 승인된 본인 독후감의 5축 기록을 방사형 차트·축별 막대·시간 변화 막대로
# 시각화한다. 축 설명 문구는 뷰에 하드코딩하지 않고 학년군(band)별 축 의미 상수에서 파생한다
# (guides_controller 관례 — 채점 규칙이 바뀌면 학생 화면 설명도 함께 바뀐다).
class GrowthsController < ApplicationController
  def show
    authorize :profile, :show?
    @timeline = StudentGrowthTimeline.new(current_user)
    @axis_hints = axis_hints
  end

  private

  # 5축 → 학년군 눈높이 설명. 밴드는 age-safe 규칙(guided_band_for — 학년 미상은 최저 밴드)을
  # 따라 설명이 실제 학년보다 어려운 문장으로 보이지 않게 한다.
  def axis_hints
    band = ReadingDomain.guided_band_for(current_user.classroom&.grade)
    meanings = ReadingDomain::AXIS_MEANINGS_BY_BAND.fetch(band, ReadingDomain::AXIS_MEANINGS_BY_BAND[:g56])
    ReadingDomain::RUBRIC_AXES.index_with { |axis| meanings[axis] }
  end
end
