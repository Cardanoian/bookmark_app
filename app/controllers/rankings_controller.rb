# 랭킹·포디움·명예의 전당(P4.10). tab = class/school/nation/challenge/hall(기본 class).
class RankingsController < ApplicationController
  TABS = %w[class school nation challenge hall].freeze

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
