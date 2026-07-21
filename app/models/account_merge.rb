# 계정 연동(MERGE) 감사 원장(account_linking_seasons_plan §Phase 2). 병합 1건 = 이 테이블 1행.
# 생존자(surviving_user, 작년 계정)와 소비된 placeholder 의 원 id(consumed_user_id — user 행은
# 병합 중 raw delete 되므로 FK 없이 역사적 사실로만 보존), 이동행 매니페스트 + pre-merge 스냅샷
# (snapshot JSON)을 남겨 되돌리기(reverse!, Phase 4)의 근거가 된다.
#
# reverse!(14일 시간창 역머지)는 Phase 4 에서 추가한다 — 여기서는 정의하지 않는다.
class AccountMerge < ApplicationRecord
  # surviving_user_id 는 NOT NULL 이지만 optional: true 로 presence 검증만 끈다(항상 서비스가
  # 세팅하고 DB 가 NOT NULL 을 강제). performed_by 는 셀프서브/총괄 경로에서 nil 일 수 있다.
  belongs_to :surviving_user, class_name: "User", optional: true
  belongs_to :performed_by, class_name: "User", optional: true

  # 아직 되돌리지 않은(활성) 병합. consumed_user_id 부분 유니크 인덱스와 짝을 이룬다.
  scope :active, -> { where(reversed_at: nil) }
end
