class AddTeacherFeedbackToReports < ActiveRecord::Migration[8.1]
  # 교사가 편집한 첨삭 텍스트(칭찬/보완/성장) 비파괴 저장. 기존 rubric(AI 원본)·teacher_rubric(점수)
  # 컬럼과 동일한 json 타입으로 두어 교사 조정 패턴을 미러한다(승인 후 학생 표시용).
  def change
    add_column :reports, :teacher_feedback, :json
  end
end
