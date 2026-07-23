# 계정 연동(MERGE) 감사 원장(account_linking_seasons_plan §Phase 2/4). 병합 1건 = 이 테이블 1행.
# 생존자(surviving_user, 작년 계정)와 소비된 placeholder 의 원 id(consumed_user_id — user 행은
# 병합 중 raw delete 되므로 FK 없이 역사적 사실로만 보존), 이동행 매니페스트 + pre-merge 스냅샷
# (snapshot JSON)을 남겨 되돌리기(reverse!)의 근거가 된다.
#
# ⚠️ **PII 보안 경계**: `snapshot` 은 **삭제된 아동 계정의 password_digest·name·소속 등 PII** 를 담는다
# (reverse! 가 신원을 정확히 복원하려면 필요). 따라서:
#   - **총괄 전용 접근**: Admin::AccountLinksController 만 원장을 열람하고, 뷰에는 요약(moved_counts·
#     from/to·수행자·시각·reversed 여부)만 렌더한다 — snapshot 원본(digest 포함)을 화면·로그·CSV
#     export 에 절대 덤프하지 않는다.
#   - **되돌리기 창 경과 후 password_digest purge**(Phase 5 야간 잡)로 보존기간을 제한한다.
class AccountMerge < ApplicationRecord
  # 이미 되돌린 병합을 다시 되돌리려 할 때(멱등 가드) 또는 되돌리기 중 유니크 충돌(제3자 tuple 점유).
  ReversalError = Class.new(StandardError)

  # 교사 되돌리기 시간창(총괄은 무제한). 이 창이 지나면 자격증명 purge 대상이 되므로, 교사 컨트롤러
  # (Teacher::AccountLinksController)와 purge 잡(Accounts::PurgeCredentialsJob)이 **이 상수 하나를 참조**해
  # 값 드리프트를 막는다(값 변경은 여기 한 곳만).
  TEACHER_REVERSE_WINDOW = 14.days

  # surviving_user_id 는 NOT NULL 이지만 optional: true 로 presence 검증만 끈다(항상 서비스가
  # 세팅하고 DB 가 NOT NULL 을 강제). performed_by 는 셀프서브/총괄 경로에서 nil 일 수 있다.
  belongs_to :surviving_user, class_name: "User", optional: true
  belongs_to :performed_by, class_name: "User", optional: true

  # 아직 되돌리지 않은(활성) 병합. consumed_user_id 부분 유니크 인덱스와 짝을 이룬다.
  scope :active, -> { where(reversed_at: nil) }

  # 병합을 되돌린다(account_linking_seasons_plan §Phase 4 B-3). 전 과정 단일 트랜잭션, 순서 엄수:
  #   1. 생존자 신원 복원(선행) — pre-merge tuple + 평생 차감 + active_monster → NEW tuple 해제.
  #   2. placeholder(NEW) 재삽입 — 원 id 재사용은 "id 공백 AND tuple 공백" 둘 다일 때만, 아니면 새 id.
  #   3. 매니페스트 자식행 원복 — 스탬프된 이동행만 NEW(또는 새 id)로, 병합-후 활동은 생존자 잔류.
  #   4. counter 재계산(표준5 reset_counters + cheers 커스텀).
  #   5. 시즌 역연산 — 생존자 현재 시즌 차감 + NEW 시즌 행 재생성.
  # **동시성 fail-closed**: 스탬프를 맨 끝이 아니라 **트랜잭션 선두에서 원자 클레임(CAS)** 으로 찍는다
  # (머지코어 조건부 claim 과 대칭). 동시 되돌리기(더블클릭)는 파괴적 복원 **이전에** 0행 클레임 →
  # 깨끗이 롤백·ReversalError. 되돌리기 중 유니크 충돌(제3자 tuple 점유 등)도 ReversalError 로 감싼다
  # (raw 500 방지 — 컨트롤러가 flash alert 로 처리).
  # **불가역**: dedup 삭제된 중복행(user_monsters 열등 개체·중복 vote/like/report/cheer·중복 game_play)은
  # 복원 불가. 새 id 발급(id_reused: false) 시 되돌린 계정 보유자는 신규 로그인 필요(requires_new_login).
  # 시간창(교사 14일)·역할 제한은 **호출 컨트롤러**가 강제한다 — 이 메서드는 되돌림 자체만 수행한다.
  def reverse!(performed_by:)
    raise ReversalError, "이미 되돌린 병합이에요." if reversed_at.present?

    data = snapshot || {}
    pre = data["old_pre_merge"] || {}
    new_attrs = data["new_attributes"] || {}
    manifest = data["manifest"] || {}
    old_id = surviving_user_id.to_i
    reversed_at_time = Time.current

    id_reused = false
    restored_new_id = nil

    transaction do
      # 원자 클레임(CAS) — 파괴적 복원 **이전에** 선점. reversed_at IS NULL 인 행만 스탬프하며, 동시
      # 되돌리기의 후행은 0행 → fail-closed 롤백(TOCTOU·raw 500 차단, 머지코어 claim 과 대칭).
      claimed = self.class.where(id: id, reversed_at: nil)
                    .update_all(reversed_at: reversed_at_time, reversed_by_id: performed_by&.id)
      raise ReversalError, "이미 되돌려진 병합입니다." unless claimed == 1

      conn = self.class.connection
      now = conn.quote(conn.quoted_date(reversed_at_time))

      restore_survivor_identity!(conn, pre, old_id, new_attrs, now)
      restored_new_id, id_reused = reinsert_placeholder!(conn, new_attrs, now)
      restore_children!(conn, manifest, restored_new_id, now)
      recompute_counters_for_reverse!(conn, manifest)
      reverse_seasons!(conn, data, old_id, restored_new_id, now)
      fixup_new_active_monster!(conn, new_attrs, restored_new_id)
    end

    { restored_new_id: restored_new_id, id_reused: id_reused, requires_new_login: !id_reused }
  rescue ActiveRecord::RecordNotUnique
    # 복원 자리(tuple)를 제3자가 점유하는 등 유니크 충돌 — 파괴적 쓰기는 트랜잭션 롤백으로 원복.
    raise ReversalError, "되돌리기 대상 자리를 다른 계정이 차지하고 있어요. 잠시 후 다시 시도해 주세요."
  end

  private

  # 1. 생존자 신원 복원(선행). identity 는 절대값(pre-merge tuple), 평생 카운터는 상대값(합산분 차감)으로
  #    되돌린다 — 병합-후 획득한 포인트/경험치는 잔류시킨다(귀속 규칙). MAX(...,0) 로 음수 방지.
  def restore_survivor_identity!(conn, pre, old_id, new_attrs, now)
    conn.execute(<<~SQL)
      UPDATE users SET
        classroom_id = #{conn.quote(pre["classroom_id"])},
        school_id = #{conn.quote(pre["school_id"])},
        name = #{conn.quote(pre["name"])},
        password_digest = #{conn.quote(pre["password_digest"])},
        mode = #{pre["mode"].to_i},
        nickname = #{conn.quote(pre["nickname"])},
        ranking_opted_in = #{conn.quote(pre["ranking_opted_in"] ? true : false)},
        experience = MAX(experience - #{new_attrs["experience"].to_i}, 0),
        points = MAX(points - #{new_attrs["points"].to_i}, 0),
        active_monster_id = #{conn.quote(pre["active_monster_id"])},
        updated_at = #{now}
      WHERE id = #{old_id}
    SQL
  end

  # 2. placeholder 재삽입. 원 id 재사용은 그 id 와 tuple(school/classroom/name)이 **둘 다 공백**일
  #    때만(rowid 재점유·tuple 충돌 방지). active_monster_id 는 NULL 로 넣고 자식 원복 후 fixup 한다.
  def reinsert_placeholder!(conn, new_attrs, now)
    original_id = consumed_user_id
    tuple_taken = User.where(school_id: new_attrs["school_id"], classroom_id: new_attrs["classroom_id"],
                             name: new_attrs["name"]).exists?
    id_taken = original_id.present? && User.where(id: original_id).exists?
    reuse = original_id.present? && !id_taken && !tuple_taken

    columns = {
      "classroom_id" => conn.quote(new_attrs["classroom_id"]),
      "school_id" => conn.quote(new_attrs["school_id"]),
      "name" => conn.quote(new_attrs["name"]),
      "password_digest" => conn.quote(new_attrs["password_digest"]),
      "email" => conn.quote(new_attrs["email"]),
      "points" => new_attrs["points"].to_i,
      "experience" => new_attrs["experience"].to_i,
      "role" => enum_int(User.roles, new_attrs["role"]),
      "mode" => enum_int(User.modes, new_attrs["mode"]),
      "nickname" => conn.quote(new_attrs["nickname"]),
      "ranking_opted_in" => conn.quote(new_attrs["ranking_opted_in"] ? true : false),
      "suspended" => conn.quote(new_attrs["suspended"] ? true : false),
      "active_monster_id" => "NULL",
      "created_at" => now,
      "updated_at" => now
    }
    columns = { "id" => original_id.to_i }.merge(columns) if reuse

    conn.execute("INSERT INTO users (#{columns.keys.join(', ')}) VALUES (#{columns.values.join(', ')})")
    new_id = reuse ? original_id.to_i : conn.select_value("SELECT last_insert_rowid()").to_i
    [ new_id, reuse ]
  end

  # enum 컬럼 값을 정수로. snapshot 의 new_attributes 는 enum 을 문자열 라벨("student"/"normal")로
  # 담으므로(User#attributes 계약) 매핑으로 정수화한다. 이미 정수면 그대로.
  def enum_int(mapping, value)
    value.is_a?(Integer) ? value : mapping.fetch(value)
  end

  # 3. 매니페스트 자식행을 NEW(또는 새 id)로 원복. 매니페스트에 없는 병합-후 활동은 생존자 잔류.
  def restore_children!(conn, manifest, new_id, now)
    Accounts::MergeService::SIMPLE_TRANSFERS.each do |table, column|
      move_rows_back(conn, table, column, manifest[table], new_id)
    end
    Accounts::MergeService::DEDUP_TABLES.each do |table, _parent, _counter|
      move_rows_back(conn, table, "user_id", manifest[table], new_id)
    end
    move_rows_back(conn, "game_plays", "user_id", manifest["game_plays"], new_id)
    restore_user_monsters!(conn, manifest["user_monsters"] || {}, new_id, now)
  end

  def move_rows_back(conn, table, column, ids, new_id)
    # 매니페스트 id 를 정수로 재캐스팅(방어심층 — 머지코어와 일관). 스탬프된 이동행만 이동하며, 14일
    # 창으로 바운드된 rowid 재사용 오귀속은 정보성 잔여라 별도 처리 불요(§5 계약).
    ids = Array(ids).map(&:to_i)
    return if ids.empty?

    conn.execute("UPDATE #{table} SET #{column} = #{new_id} WHERE id IN (#{ids.join(',')})")
  end

  # user_monsters: transferred 는 NEW 로 이관 복원, promoted 는 OLD 행 species 를 승격 전으로 되돌리고
  # NEW 의 우월 개체를 재생성한다(celebrated_at·nickname 은 소실 — 미관, §5 문서화). 열등 dropped 는 불가역.
  def restore_user_monsters!(conn, um, new_id, now)
    move_rows_back(conn, "user_monsters", "user_id", um["transferred"], new_id)

    Array(um["promoted"]).each do |promo|
      conn.execute(<<~SQL)
        UPDATE user_monsters
        SET monster_species_id = #{promo["prev_species_id"].to_i},
            evolved_at = #{conn.quote(promo["prev_evolved_at"])},
            updated_at = #{now}
        WHERE id = #{promo["old_um_id"].to_i}
      SQL

      species_id = promo["new_species_id"].to_i
      dex_no = MonsterSpecies.where(id: species_id).pick(:dex_no).to_i
      conn.execute(<<~SQL)
        INSERT INTO user_monsters (user_id, monster_species_id, dex_no, obtained_at, created_at, updated_at)
        VALUES (#{new_id}, #{species_id}, #{dex_no}, #{now}, #{now}, #{now})
      SQL
    end
  end

  # 4. counter 재계산(이관 복원된 행의 부모). §Phase2 step5 와 동일 2분기(표준5 reset_counters / cheers 커스텀).
  def recompute_counters_for_reverse!(conn, manifest)
    Accounts::MergeService::DEDUP_TABLES.each do |table, parent, counter|
      next unless counter

      ids = Array(manifest[table]).map(&:to_i)
      next if ids.empty?

      parent_ids = conn.select_values("SELECT DISTINCT #{parent} FROM #{table} WHERE id IN (#{ids.join(',')})").map(&:to_i)
      next if parent_ids.empty?

      if counter == :cheers
        parent_ids.each do |board_post_id|
          board_post = BoardPost.find_by(id: board_post_id)
          next unless board_post

          board_post.report.update_columns(cheers_count: board_post.cheers.count)
        end
      else
        model = counter[0].constantize
        parent_ids.each { |parent_id| model.reset_counters(parent_id, counter[1]) }
      end
    end
  end

  # 5. 시즌 역연산. 생존자 현재 시즌에서 병합 이관분(new_season_scores)을 차감하고(병합-후 누적은 잔류),
  #    병합이 새로 만든 생존자 시즌 행(원래 없던 학년도)이 0 이 되면 제거한 뒤, NEW 시즌 행을 재생성한다.
  def reverse_seasons!(conn, data, old_id, new_id, now)
    old_years = Array(data["old_season_scores"]).map { |row| row["academic_year"] }.to_set
    new_attrs = data["new_attributes"] || {}

    Array(data["new_season_scores"]).each do |row|
      year = row["academic_year"].to_i
      exp = row["experience_earned"].to_i
      pts = row["points_earned"].to_i

      conn.execute(<<~SQL)
        UPDATE season_scores
        SET experience_earned = MAX(experience_earned - #{exp}, 0),
            points_earned = MAX(points_earned - #{pts}, 0),
            updated_at = #{now}
        WHERE user_id = #{old_id} AND academic_year = #{year}
      SQL

      unless old_years.include?(row["academic_year"])
        conn.execute(<<~SQL)
          DELETE FROM season_scores
          WHERE user_id = #{old_id} AND academic_year = #{year}
            AND experience_earned = 0 AND points_earned = 0
        SQL
      end

      conn.execute(<<~SQL)
        INSERT INTO season_scores
          (academic_year, user_id, experience_earned, points_earned, school_id, classroom_id, grade, created_at, updated_at)
        VALUES
          (#{year}, #{new_id}, #{exp}, #{pts},
           #{conn.quote(new_attrs["school_id"])}, #{conn.quote(new_attrs["classroom_id"])}, NULL, #{now}, #{now})
      SQL
    end
  end

  # NEW active_monster 복원(가능할 때만). 원 active user_monster 가 자식 원복으로 다시 NEW 소속이면
  # 복원하고, 아니면(승격 소실·이관 안 됨) NULL 로 둔다(dangling FK 방지).
  def fixup_new_active_monster!(conn, new_attrs, new_id)
    original = new_attrs["active_monster_id"]
    return if original.nil?

    conn.execute(<<~SQL)
      UPDATE users SET active_monster_id = #{original.to_i}
      WHERE id = #{new_id}
        AND EXISTS (SELECT 1 FROM user_monsters WHERE id = #{original.to_i} AND user_id = #{new_id})
    SQL
  end
end
