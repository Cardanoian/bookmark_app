# 자동 저장 표를 둘로 나눈다(2026-09-13, 자동 저장 3차 코드 리뷰 후속 — docs/improve 통합정리 §5-1c).
#
# 20260913000001 의 autosave_key 하나가 "초안을 만든 화면"(첫 저장 재시도가 초안을 또 만들지 않게)과
# "마지막으로 쓴 화면"(응답만 잃은 재전송을 거짓 충돌로 보지 않게) 두 일을 함께 했다. 둘은 다르다:
# 다른 탭이 그 초안을 저장하면 "마지막으로 쓴 화면"이 바뀌어, 첫 화면의 재시도가 제 초안을 못 찾고
# 한 편을 더 만들었다(리뷰 L1). 이제 autosave_key 는 **만든 화면**(create 때 한 번, 바꾸지 않음)이다.
#
# autosave_writer_key — 이 초안을 마지막으로 저장한 화면의 표. 표 없이 온 저장(담임·스크립트 없는
#   화면)은 비운다 — 학생 옛 탭이 "마지막으로 쓴 것이 나"라며 담임 수정을 덮지 않게(M2).
# autosave_seq — 그 화면 안에서 요청을 보낸 순번(브라우저의 입력 횟수, 단조 증가). 같은 화면이라도
#   더 앞선 순번의 요청은 받지 않는다 — 늦게 도착한 옛 요청이 새 글을 되돌리지 않게(M1).
#   같은 순번(응답만 잃은 재전송)은 같은 내용이라 받는다.
# 둘 다 행 단위 비교만 하므로 인덱스는 두지 않는다.
class AddAutosaveWriterToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :autosave_writer_key, :string, limit: 64
    add_column :reports, :autosave_seq, :integer
  end
end
