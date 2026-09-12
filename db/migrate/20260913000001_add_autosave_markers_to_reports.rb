# 자동 저장이 초안 행에 남기는 표 두 가지(2026-09-13, 자동 저장 2차 코드 리뷰 후속).
#
# autosave_key — 이 초안을 마지막으로 저장한 **편집 화면**의 표(화면을 열 때마다 브라우저가 새로 만든다).
#   · 첫 저장(create)이 시간 초과로 끊겨 다시 와도 같은 표면 새 초안을 만들지 않고 그 초안을 잇는다.
#   · 응답만 잃고 다시 보낸 저장은 버전이 뒤처져도 "다른 곳에서 고쳤다"로 거절하지 않는다 — 마지막으로
#     쓴 것이 바로 이 화면이라서다. 다른 탭·기기가 사이에 저장했으면 표가 달라 여전히 거절한다.
#   한 사용자 안에서 유일하다(화면 하나는 초안 하나만 다룬다). 표가 없는 행(예전 글·사진 초안)은 제외.
#
# autosave_origin_digest — 첫 저장을 보낸 새 글 화면 주소(/reports/new?…)의 SHA-256 지문.
#   새로고침·뒤로 가기·앱이 처음 주소로 화면을 다시 열면 빈 새 글 대신 이 초안을 연다. 예전에는 주소
#   원문을 세션 쿠키에 넣었는데, 단계 학습은 본문 전체를 주소에 실어 넘겨 쿠키 한도(4KB)를 넘겼다
#   (첫 저장이 500 → 재시도마다 초안이 늘어남). 쿠키가 아니라 행에 두면 동시 요청이 쿠키를 되써
#   기억이 사라지는 문제도 없다.
class AddAutosaveMarkersToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :autosave_key, :string, limit: 64
    add_column :reports, :autosave_origin_digest, :string, limit: 64

    add_index :reports, [ :user_id, :autosave_key ], unique: true, where: "autosave_key IS NOT NULL",
              name: "index_reports_on_user_id_and_autosave_key"
    add_index :reports, [ :user_id, :autosave_origin_digest ], where: "autosave_origin_digest IS NOT NULL",
              name: "index_reports_on_user_id_and_autosave_origin_digest"
  end
end
