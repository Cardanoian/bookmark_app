# 학생 출제 기여(내가 낸 문제) 표시 헬퍼 — 문제 유형·검토 상태를 학생 눈높이 라벨과 배지 색으로 바꾼다.
# 내가 낸 문제 목록(quiz_contributions/index)과 이 책의 내 기록(library_books/show)이 같은 카드
# 파셜(quiz_contributions/_contribution)을 쓰므로 라벨을 한 곳에 둔다.
module QuizContributionsHelper
  CONTRIBUTION_AXES = {
    "mcq"         => [ :quiz, "객관식 퀴즈" ],
    "hint_reveal" => [ :detective, "나는 누구게?" ]
  }.freeze

  # 반려는 이유를 저장하지 않으므로 학생을 탓하지 않는 중립 문구로만 쓴다.
  CONTRIBUTION_STATUSES = {
    "pending"  => [ "선생님 확인 중", "badge-neutral" ],
    "approved" => [ "문제은행에 들어갔어요", "badge-success" ],
    "rejected" => [ "이번에는 뽑히지 않았어요", "badge-yellow" ]
  }.freeze

  # [아이콘, 라벨]
  def contribution_axis_meta(contribution)
    CONTRIBUTION_AXES.fetch(contribution.content_axis, [ :quiz, "문제" ])
  end

  # [라벨, 배지 클래스]
  def contribution_status_meta(status)
    CONTRIBUTION_STATUSES.fetch(status.to_s, [ status.to_s, "badge-neutral" ])
  end
end
