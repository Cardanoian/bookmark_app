class RankingPreferencesController < ApplicationController
  skip_before_action :require_student_ranking_profile

  def edit
    authorize :profile, :show?
  end

  def update
    authorize :profile, :show?

    unless explicit_participation_choice?
      current_user.assign_attributes(ranking_preference_params.except(:ranking_opted_in))
      current_user.errors.add(:ranking_opted_in, "여부를 선택해 주세요.")
      return render :edit, status: :unprocessable_entity
    end

    was_opted_in = current_user.ranking_opted_in?
    if current_user.update(ranking_preference_params)
      remove_stale_ranking_row if was_opted_in && !current_user.ranking_opted_in?
      current_user.broadcast_ranking_change if current_user.ranking_opted_in?
      redirect_to growth_path, notice: "닉네임과 랭킹 참여 설정을 저장했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def ranking_preference_params
    params.require(:user).permit(:nickname, :ranking_opted_in)
  end

  def explicit_participation_choice?
    %w[0 1].include?(params.dig(:user, :ranking_opted_in).to_s)
  end

  def remove_stale_ranking_row
    return unless current_user.classroom

    Turbo::StreamsChannel.broadcast_remove_to(
      [ current_user.classroom, :ranking ],
      target: ActionView::RecordIdentifier.dom_id(current_user, :ranking)
    )
  end
end
