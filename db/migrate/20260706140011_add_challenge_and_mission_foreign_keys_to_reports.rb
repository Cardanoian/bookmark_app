class AddChallengeAndMissionForeignKeysToReports < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :reports, :challenges
    add_foreign_key :reports, :missions
  end
end
