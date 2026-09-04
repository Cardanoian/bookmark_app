class AuditLog < ApplicationRecord
  ACTION_LABELS = {
    "teacher.student_delete" => "학생 계정 삭제",
    "teacher.password_reset" => "학생 비밀번호 초기화",
    "teacher.points_grant" => "학생 포인트 지급",
    # CSV 시절 키. 지난 원장 행들이 이 이름으로 남아 있어 라벨을 지우지 않는다.
    "teacher.reports_csv_download" => "교사 연구자료 CSV 다운로드(구)",
    "teacher.reports_xlsx_download" => "교사 연구자료 엑셀 다운로드",
    "teacher.mission_delete" => "미션 삭제",
    "teacher.quiz_delete" => "교사 퀴즈 삭제",
    "staff.challenge_delete" => "챌린지 삭제",
    "admin.user_update" => "사용자 정보 수정",
    "admin.points_adjust" => "사용자 포인트 조정",
    "admin.account_suspend" => "계정 정지",
    "admin.account_unsuspend" => "계정 정지 해제",
    "admin.password_reset" => "사용자 비밀번호 초기화",
    "admin.role_change" => "사용자 역할 변경",
    "admin.school_delete" => "학교 삭제",
    "admin.book_delete" => "도서 삭제",
    "admin.quiz_delete" => "관리자 퀴즈 삭제",
    "admin.badge_delete" => "뱃지 삭제",
    "admin.monster_species_delete" => "몬스터 삭제",
    "admin.game_content_delete" => "게임 콘텐츠 삭제",
    "admin.analytics_csv_download" => "관리자 통계 CSV 다운로드"
  }.freeze

  belongs_to :actor, class_name: "User", optional: true

  validates :actor_role, :action, presence: true
  validates :action, length: { maximum: 100 }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def action_label
    ACTION_LABELS.fetch(action, action)
  end

  # 감사 원장은 생성 후 수정·삭제할 수 없는 append-only 기록이다.
  def readonly?
    persisted?
  end
end
