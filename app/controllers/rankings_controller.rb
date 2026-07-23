# 랭킹·포디움·명예의 전당(P4.10). tab = class/grade/school/nation/challenge/hall(기본 class).
# grade = 시즌제(§Phase 1) 학년 개인 순위 탭.
class RankingsController < ApplicationController
  TABS = %w[class grade school nation challenge hall].freeze

  def index
    authorize :ranking, :index?
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "class"
    @board = RankingBoard.new(current_user)
    load_tab
  end

  private

  def load_tab
    case @tab
    when "class"
      @ranking = @board.class_ranking
      @podium = @board.podium
    when "grade"
      @ranking = @board.grade_ranking
    when "school"
      @ranking = @board.school_ranking
    when "nation"
      @ranking = @board.nation_ranking
    when "challenge"
      @challenge = Challenge.order(created_at: :desc).first
      @ranking = @board.challenge_ranking(@challenge)
    when "hall"
      @ranking = @board.hall_of_fame
    end
  end
end
