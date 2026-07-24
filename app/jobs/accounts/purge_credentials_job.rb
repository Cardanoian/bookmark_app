# 계정 연동 자격증명 purge(account_linking_seasons_plan §Phase 5). 되돌리기 창(교사 14일) 이 지난
# **미되돌림(active)** 병합의 `snapshot` 에서 `password_digest`(old_pre_merge·new_attributes 양쪽)만
# nullify 해 삭제된 아동 계정의 PII 보존기간을 제한한다. snapshot 의 나머지(매니페스트·시즌·평생
# 스냅샷)는 보존한다 — 총괄의 구조 reverse(신원 복원) 자체는 여전히 가능하게.
#
# **주의(운영 계약)**: purge 후에도 총괄 reverse 는 구조를 복원하지만, 복원된 placeholder 는
# password_digest 가 없어 **로그인 불가** → 담임이 학생관리에서 비밀번호를 재설정해야 한다.
#
# 멱등: digest 가 이미 nil 이면 아무것도 쓰지 않는다. `account_links:purge_credentials` rake 와
# 야간 recurring(config/recurring.yml)이 공유한다. now: 주입으로 창 경계 테스트 가능.
module Accounts
  class PurgeCredentialsJob < ApplicationJob
    queue_as :default

    # 교사 되돌리기 창(AccountMerge::TEACHER_REVERSE_WINDOW = 14일)과 **단일 상수 공유**. 이 창이
    # 지나면 교사는 되돌릴 수 없고(총괄만) digest 를 보존할 이유가 사라진다.
    PURGE_WINDOW = AccountMerge::TEACHER_REVERSE_WINDOW

    SECTIONS = %w[old_pre_merge new_attributes].freeze

    def perform(now: Time.current)
      cutoff = now - PURGE_WINDOW
      scanned = 0
      purged = 0

      AccountMerge.active.where("created_at < ?", cutoff).find_each do |merge|
        scanned += 1
        purged += 1 if purge_snapshot!(merge)
      end

      { scanned: scanned, purged: purged }
    end

    private

    # merge.snapshot 의 두 섹션에서 password_digest 를 nullify. 하나라도 바꿨으면 true.
    def purge_snapshot!(merge)
      snapshot = merge.snapshot
      return false unless snapshot.is_a?(Hash)

      changed = false
      SECTIONS.each do |section|
        next unless snapshot[section].is_a?(Hash)
        next if snapshot[section]["password_digest"].blank?

        snapshot[section]["password_digest"] = nil
        changed = true
      end
      return false unless changed

      merge.update_columns(snapshot: snapshot) # 콜백·검증 우회(감사 원장 무결성 갱신)
      true
    end
  end
end
