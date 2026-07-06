# 전역/학교 챌린지 참여(P4.11). join → 세션 플래그로 다음 작성 독후감에 challenge_id 연결.
class ChallengesController < ApplicationController
  before_action :set_challenge, only: [ :show, :join ]

  def index
    authorize :challenge, :index?
    @challenges = joinable_challenges.order(created_at: :desc)
  end

  def show
    authorize :challenge, :show?
  end

  def join
    authorize :challenge, :join?
    return head :forbidden unless joinable?(@challenge)

    session[:active_challenge_id] = @challenge.id
    redirect_to new_report_path, notice: "‘#{@challenge.title}’ 챌린지에 참여했어요. 독후감을 써 볼까요?"
  end

  private

  def set_challenge
    @challenge = Challenge.find(params[:id])
  end

  # 전역 챌린지 + 소속 학교 챌린지.
  def joinable_challenges
    Challenge.where(scope: :global).or(Challenge.where(scope: :school, school_id: current_user.school_id))
  end

  def joinable?(challenge)
    challenge.global? || challenge.school_id == current_user.school_id
  end
end
