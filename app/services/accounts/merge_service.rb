# 계정 연동(MERGE) 코어(account_linking_seasons_plan §Phase 2). 학년이 바뀌면 새 담임이 만든
# **현재 학년도 placeholder 계정(new)** 을 접어 삭제하고, 작년 기록을 가진 **작년 계정(old)** 을
# 생존자로 남긴다. 생존자는 placeholder 의 학급·학교·이름·비번·모드(현재 학년도 신원)를 승계한다.
#
# 계약(§1.1 원칙 3): 전 과정은 **하나의 ApplicationRecord.transaction** 이다. 매니페스트 + pre-merge
# 스냅샷을 account_merges 원장에 남겨 실질 가역(reverse!, Phase 4)이고, dedup 으로 삭제된 중복행만
# **불가역**(snapshot 에 표시)이다. 커밋 후 사이드이펙트(reload·뱃지·진화·시즌 방송·세션 스왑)는
# 서비스가 아니라 **호출자(컨트롤러, Phase 3/4)** 책임이다 — call 은 Result 구조체만 돌려준다.
module Accounts
  class MergeService
    # 병합 결과. ok=성공 여부, error_code=실패 사유(가드/동시성). 호출자는 ok? 로 분기해 커밋 후
    # 사이드이펙트(run_post_commit_side_effects!)·세션 스왑을 돌린다.
    Result = Struct.new(:ok, :surviving_user, :account_merge, :error_code, keyword_init: true) do
      def ok?
        ok
      end
    end

    # 가드/동시성 위반을 코드와 함께 트랜잭션 안에서 raise 해 롤백시키는 내부 예외.
    class MergeError < StandardError
      attr_reader :code

      def initialize(code, message = nil)
        @code = code
        super(message || code.to_s)
      end
    end

    # [table, user_column] — 단순 이관(중복 유니크 없음: UPDATE user_id/by_user_id/imported_by_id 만).
    # book_intros·book_sequels 는 user_id NOT NULL + FK RESTRICT 라 미이관 시 placeholder 삭제가
    # FK abort 된다 — 반드시 포함. quiz_contributions(cascade)·recommendation_imports(nullify)는
    # 미이관 시 소리 없이 정리/절단되므로 감사 보존을 위해 이관한다.
    SIMPLE_TRANSFERS = [
      [ "quiz_attempts", "user_id" ],
      [ "reports", "user_id" ],
      [ "forum_posts", "user_id" ],
      [ "book_intros", "user_id" ],
      [ "book_sequels", "user_id" ],
      [ "quiz_contributions", "user_id" ],
      [ "stickers", "by_user_id" ],
      [ "recommendation_imports", "imported_by_id" ]
    ].freeze

    # 생존자-우선 dedup 대상: [table, parent_column, counter]. counter 는 삭제로 카운트가 바뀌는
    # 충돌 부모의 재집계 방식이다. 표준 belongs_to counter_cache 5종은 reset_counters([model, assoc]),
    # cheers 는 비표준(reports.cheers_count · board_post delegate)이라 :cheers 커스텀으로 분기한다.
    DEDUP_TABLES = [
      [ "user_badges",        "badge_id",        nil ],
      [ "mission_participations", "mission_id",  nil ],
      [ "cheers",             "board_post_id",   :cheers ],
      [ "book_intro_votes",   "book_intro_id",   [ "BookIntro",  :book_intro_votes ] ],
      [ "book_sequel_votes",  "book_sequel_id",  [ "BookSequel", :book_sequel_votes ] ],
      [ "forum_post_likes",   "forum_post_id",   [ "ForumPost",  :forum_post_likes ] ],
      [ "forum_post_reports", "forum_post_id",   [ "ForumPost",  :forum_post_reports ] ],
      [ "quiz_reports",       "quiz_id",         [ "Quiz",       :quiz_reports ] ]
    ].freeze

    def initialize(old_account:, new_account:, performed_by:)
      @old = old_account
      @new = new_account
      @performed_by = performed_by
    end

    # 부작용 없이 **생존자(작년 계정)가 되찾는 자산** 요약을 돌려준다. Phase 3 확인화면의
    # "작년 N학년 M반 XXX — 독후감 N·몬스터 M·1,240P·Lv.k 를 가져옵니다" 문구 소스.
    # (실제로 물리 이동하는 것은 placeholder(new)의 행이지만, 학생이 궁금해하는 건 작년 자산이므로
    #  생존자 기준으로 집계한다. 이동행 카운트는 감사의 moved_counts 에 별도로 남는다.)
    def preview
      {
        reports: Report.where(user_id: @old.id).count,
        monsters: UserMonster.where(user_id: @old.id).distinct.count(:dex_no),
        points: @old.points,
        experience: @old.experience,
        trainer_level: @old.trainer_level,
        badges: UserBadge.where(user_id: @old.id).count
      }
    end

    # 전 과정 단일 트랜잭션. 성공 시 Result(ok: true, ...), 가드/동시성 위반 시 롤백 + Result(ok: false).
    def call
      ApplicationRecord.transaction do
        guard!
        @snapshot = capture_snapshot
        detach_new_active_monster!
        reparent_children!
        recompute_counters!
        merge_lifetime_and_season!
        delete_placeholder_and_claim!
        account_merge = write_audit!
        Result.new(ok: true, surviving_user: @old, account_merge: account_merge, error_code: nil)
      end
    rescue MergeError => error
      Result.new(ok: false, surviving_user: nil, account_merge: nil, error_code: error.code)
    end

    # 커밋 후 사이드이펙트 헬퍼(선택). **call 밖에서** 호출자가 실행한다 — 트랜잭션 안에서
    # reload·방송·해금을 하면 롤백 오염/조기 방송이 되므로 커밋 후에만 돌린다(§0.3 대칭).
    def run_post_commit_side_effects!(survivor)
      survivor.run_point_side_effects!
      MonsterUnlock.new(survivor).evaluate!
    end

    private

    def conn
      @conn ||= ApplicationRecord.connection
    end

    # 1. 가드(사전점검). 위반 시 코드와 함께 raise → 롤백.
    def guard!
      raise MergeError.new(:not_students) unless @old&.student? && @new&.student?
      raise MergeError.new(:same_account) if @old.id == @new.id

      current = Classroom.current_academic_year
      old_year = @old.classroom&.academic_year
      new_year = @new.classroom&.academic_year
      raise MergeError.new(:invalid_source) unless old_year && old_year < current
      raise MergeError.new(:invalid_target) unless new_year && new_year == current
      raise MergeError.new(:suspended) if @old.suspended? || @new.suspended?
    end

    # 2. 매니페스트·스냅샷 캡처(이동 전). old pre-merge tuple + 시즌 스냅샷 + new 전체 속성.
    #    manifest·dropped 는 reparent 중 채운다.
    def capture_snapshot
      {
        "old_pre_merge" => {
          "classroom_id" => @old.classroom_id,
          "school_id" => @old.school_id,
          "name" => @old.name,
          "password_digest" => @old.password_digest,
          "mode" => User.modes.fetch(@old.mode),
          "points" => @old.points,
          "experience" => @old.experience,
          "active_monster_id" => @old.active_monster_id
        },
        "new_attributes" => @new.attributes,
        "old_season_scores" => season_snapshot(@old.id),
        "new_season_scores" => season_snapshot(@new.id),
        "manifest" => {},
        "dropped" => {}
      }
    end

    def season_snapshot(user_id)
      SeasonScore.where(user_id: user_id)
                 .pluck(:academic_year, :experience_earned, :points_earned)
                 .map { |year, exp, pts| { "academic_year" => year, "experience_earned" => exp, "points_earned" => pts } }
    end

    # 3. active_monster 해제(NEW 쪽만). OLD active 행은 in-place 승격으로 삭제되지 않으므로 불건드림.
    def detach_new_active_monster!
      conn.execute("UPDATE users SET active_monster_id = NULL, updated_at = #{quoted_now} WHERE id = #{@new.id.to_i}")
    end

    # 4. 자식 재부모화. user_monsters in-place 승격 / 생존자-우선 dedup / 단순 이관.
    #    @dedup(counter 재계산용 충돌 부모)·manifest·dropped·moved_counts 를 채운다.
    def reparent_children!
      @dedup = {}
      manifest = @snapshot["manifest"]
      dropped = @snapshot["dropped"]

      um = reparent_user_monsters!
      manifest["user_monsters"] = um
      dropped["user_monsters"] = um["dropped_new"]

      SIMPLE_TRANSFERS.each do |table, column|
        ids = conn.select_values("SELECT id FROM #{table} WHERE #{column} = #{@new.id.to_i}").map(&:to_i)
        conn.execute("UPDATE #{table} SET #{column} = #{@old.id.to_i} WHERE #{column} = #{@new.id.to_i}") if ids.any?
        manifest[table] = ids
      end

      DEDUP_TABLES.each do |table, parent, counter|
        result = dedup_survivor_first(table, parent)
        @dedup[table] = result.merge(counter: counter)
        manifest[table] = result[:transferred]
        dropped[table] = result[:dropped]
      end

      gp = dedup_game_plays
      @dedup["game_plays"] = gp
      manifest["game_plays"] = gp[:transferred]
      dropped["game_plays"] = gp[:dropped]

      @moved_counts = build_moved_counts(manifest)
    end

    # user_monsters in-place 승격: 라인(dex_no)당 1행 유니크[user_id, dex_no].
    #  - 충돌(둘 다 보유): stage 비교 — NEW 우월이면 OLD 그 dex 행을 NEW species/evolved_at 로 제자리
    #    승격(id·celebrated_at·nickname 보존 → OLD.active_monster_id 무효화 없음) 후 NEW 행 DELETE;
    #    OLD 우월/동률이면 NEW 행만 DELETE.
    #  - 비충돌(NEW 만 보유): 단순 user_id 이관.
    def reparent_user_monsters!
      old_id = @old.id.to_i
      new_id = @new.id.to_i

      conflicts = conn.select_all(<<~SQL).to_a
        SELECT n.id AS new_um_id, n.dex_no AS dex_no,
               n.monster_species_id AS new_species_id, n.evolved_at AS new_evolved_at,
               o.id AS old_um_id, o.monster_species_id AS old_species_id, o.evolved_at AS old_evolved_at
        FROM user_monsters n
        JOIN user_monsters o ON o.user_id = #{old_id} AND o.dex_no = n.dex_no
        WHERE n.user_id = #{new_id}
      SQL

      promoted = []
      dropped_new = []

      conflicts.each do |row|
        new_um_id = row["new_um_id"].to_i
        new_species_id = row["new_species_id"].to_i
        old_um_id = row["old_um_id"].to_i
        if species_stage(new_species_id) > species_stage(row["old_species_id"])
          # NEW 우월 → OLD 그 dex 행을 제자리 승격(id 불변 → active_monster_id 보존, celebrated_at·nickname 유지).
          conn.execute(<<~SQL)
            UPDATE user_monsters
            SET monster_species_id = #{new_species_id},
                evolved_at = #{conn.quote(row["new_evolved_at"])},
                updated_at = #{quoted_now}
            WHERE id = #{old_um_id}
          SQL
          promoted << {
            "old_um_id" => old_um_id,
            "prev_species_id" => row["old_species_id"].to_i,
            "prev_evolved_at" => row["old_evolved_at"],
            "new_species_id" => new_species_id
          }
        end
        conn.execute("DELETE FROM user_monsters WHERE id = #{new_um_id}")
        dropped_new << new_um_id
      end

      transferred = conn.select_values("SELECT id FROM user_monsters WHERE user_id = #{new_id}").map(&:to_i)
      conn.execute("UPDATE user_monsters SET user_id = #{old_id} WHERE user_id = #{new_id}") if transferred.any?

      { "transferred" => transferred, "promoted" => promoted, "dropped_new" => dropped_new }
    end

    # 생존자-우선 dedup(유니크 [parent, user_id]): 충돌 NEW 행 삭제 + 나머지 이관. 충돌 부모 id 는
    # 삭제 **전** 수집(counter 재계산 대상). dropped 는 불가역 표시로 snapshot 에 남긴다.
    def dedup_survivor_first(table, parent)
      old_id = @old.id.to_i
      new_id = @new.id.to_i

      conflict_parents = conn.select_values(<<~SQL).map(&:to_i)
        SELECT DISTINCT n.#{parent} FROM #{table} n
        WHERE n.user_id = #{new_id}
          AND EXISTS (SELECT 1 FROM #{table} o WHERE o.user_id = #{old_id} AND o.#{parent} = n.#{parent})
      SQL

      dropped = conn.select_values(<<~SQL).map(&:to_i)
        SELECT n.id FROM #{table} n
        WHERE n.user_id = #{new_id}
          AND EXISTS (SELECT 1 FROM #{table} o WHERE o.user_id = #{old_id} AND o.#{parent} = n.#{parent})
      SQL

      conn.execute("DELETE FROM #{table} WHERE id IN (#{dropped.join(',')})") if dropped.any?

      transferred = conn.select_values("SELECT id FROM #{table} WHERE user_id = #{new_id}").map(&:to_i)
      conn.execute("UPDATE #{table} SET user_id = #{old_id} WHERE user_id = #{new_id}") if transferred.any?

      { conflict_parents: conflict_parents, dropped: dropped, transferred: transferred }
    end

    # game_plays 는 부분 유니크 2종([game_type, book_id, played_on] WHERE book_id NOT NULL /
    # [game_type, played_on] WHERE book_id NULL)이라 book_id NULL 대칭까지 맞춘 EXISTS 로 충돌 판정.
    def dedup_game_plays
      old_id = @old.id.to_i
      new_id = @new.id.to_i

      dropped = conn.select_values(<<~SQL).map(&:to_i)
        SELECT n.id FROM game_plays n
        WHERE n.user_id = #{new_id} AND EXISTS (
          SELECT 1 FROM game_plays o
          WHERE o.user_id = #{old_id} AND o.game_type = n.game_type AND o.played_on = n.played_on
            AND ((o.book_id IS NULL AND n.book_id IS NULL) OR o.book_id = n.book_id)
        )
      SQL

      conn.execute("DELETE FROM game_plays WHERE id IN (#{dropped.join(',')})") if dropped.any?

      transferred = conn.select_values("SELECT id FROM game_plays WHERE user_id = #{new_id}").map(&:to_i)
      conn.execute("UPDATE game_plays SET user_id = #{old_id} WHERE user_id = #{new_id}") if transferred.any?

      { dropped: dropped, transferred: transferred }
    end

    # 5. counter 재계산. 표준 5종은 reset_counters(충돌 부모만), cheers 는 커스텀 update_columns.
    #    #forum_post_reports·#quiz_reports 의 hide/reported 플래그는 재평가하지 않는다(sticky) — counter 만.
    def recompute_counters!
      DEDUP_TABLES.each do |table, _parent, counter|
        next unless counter

        result = @dedup[table]
        parents = Array(result[:conflict_parents])
        next if parents.empty?

        if counter == :cheers
          parents.each do |board_post_id|
            board_post = BoardPost.find_by(id: board_post_id)
            next unless board_post

            # cheers_count 는 비표준(reports 컬럼, board_post delegate). 제3자 report 검증·콜백을
            # 건드리지 않도록 update_columns 로 board_post.cheers.count 만 반영한다.
            board_post.report.update_columns(cheers_count: board_post.cheers.count)
          end
        else
          model = counter[0].constantize
          assoc = counter[1]
          parents.each { |parent_id| model.reset_counters(parent_id, assoc) }
        end
      end
    end

    # 6. 평생 합산 + 시즌 sum-and-delete. 평생 자산(users.experience/points)은 불변 이월,
    #    시즌은 NEW 의 학년도별 행을 OLD 로 합산(ON CONFLICT) 후 NEW 시즌 행 전량 삭제.
    def merge_lifetime_and_season!
      conn.execute(<<~SQL)
        UPDATE users
        SET points = points + #{@new.points.to_i},
            experience = experience + #{@new.experience.to_i},
            updated_at = #{quoted_now}
        WHERE id = #{@old.id.to_i}
      SQL

      conn.execute(<<~SQL)
        INSERT INTO season_scores
          (academic_year, user_id, experience_earned, points_earned, school_id, classroom_id, grade, created_at, updated_at)
        SELECT academic_year, #{@old.id.to_i}, experience_earned, points_earned, school_id, classroom_id, grade, #{quoted_now}, #{quoted_now}
        FROM season_scores WHERE user_id = #{@new.id.to_i}
        ON CONFLICT(academic_year, user_id) DO UPDATE SET
          experience_earned = season_scores.experience_earned + excluded.experience_earned,
          points_earned = season_scores.points_earned + excluded.points_earned,
          updated_at = excluded.updated_at
      SQL

      conn.execute("DELETE FROM season_scores WHERE user_id = #{@new.id.to_i}")
    end

    # 7. placeholder 삭제(raw delete_all — dependent: :destroy CASCADE 소실 방지, 미이관 시 abort=fail-closed)
    #    + 조건부 claim 승계. placeholder 선삭제로 [school_id, classroom_id, name] 유니크 미충돌.
    #    claim WHERE 에 pre-merge tuple 을 토큰으로 걸어 동시 이중병합을 affected 0 → 롤백으로 차단한다.
    def delete_placeholder_and_claim!
      User.where(id: @new.id).delete_all

      pre = @snapshot["old_pre_merge"]
      affected = User.where(id: @old.id, classroom_id: pre["classroom_id"], school_id: pre["school_id"])
                     .update_all(
                       classroom_id: @new.classroom_id,
                       school_id: @new.school_id,
                       name: @new.name,
                       password_digest: @new.password_digest,
                       mode: User.modes.fetch(@new.mode),
                       updated_at: Time.current
                     )
      raise MergeError.new(:claim_conflict) if affected.zero?
    end

    # 8. 감사 기록.
    def write_audit!
      pre = @snapshot["old_pre_merge"]
      AccountMerge.create!(
        surviving_user_id: @old.id,
        consumed_user_id: @new.id,
        performed_by_id: @performed_by&.id,
        performed_by_role: @performed_by && User.roles[@performed_by.role],
        from_classroom_id: pre["classroom_id"],
        to_classroom_id: @new.classroom_id,
        from_school_id: pre["school_id"],
        to_school_id: @new.school_id,
        moved_counts: @moved_counts,
        snapshot: @snapshot
      )
    end

    # 이동 요약(감사·통계). 매니페스트 크기에서 유도.
    def build_moved_counts(manifest)
      um = manifest["user_monsters"]
      {
        "reports" => manifest["reports"].size,
        "monsters" => (um["transferred"].size + um["promoted"].size),
        "points" => @new.points.to_i,
        "experience" => @new.experience.to_i,
        "badges" => manifest["user_badges"].size,
        "forum_posts" => manifest["forum_posts"].size,
        "quiz_attempts" => manifest["quiz_attempts"].size,
        "game_plays" => manifest["game_plays"].size,
        "book_intros" => manifest["book_intros"].size,
        "book_sequels" => manifest["book_sequels"].size
      }
    end

    # monster_species.stage 조회(전 종 1회 로드 캐시 — 72행이라 저렴). nil species → 0.
    def species_stage(species_id)
      @species_stages ||= MonsterSpecies.pluck(:id, :stage).to_h
      @species_stages[species_id.to_i].to_i
    end

    def quoted_now
      conn.quote(conn.quoted_date(Time.current))
    end
  end
end
