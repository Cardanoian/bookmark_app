require "test_helper"

# 계정 연동 감사 원장 모델(account_linking_seasons_plan §Phase 2) — 연관·active 스코프.
class AccountMergeTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "원장초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @survivor = User.create!(school: @school, classroom: @classroom, name: "생존자", password: "password")
    @performer = User.create!(school: @school, classroom: @classroom, name: "수행교사",
                              role: :teacher, password: "password", email: "perf@example.com")
  end

  test "surviving_user 와 performed_by 연관을 노출한다" do
    merge = AccountMerge.create!(
      surviving_user_id: @survivor.id,
      consumed_user_id: 9_999, # 삭제된 placeholder 의 역사적 원 id(실 user 없음)
      performed_by_id: @performer.id,
      performed_by_role: User.roles[@performer.role]
    )

    assert_equal @survivor, merge.surviving_user
    assert_equal @performer, merge.performed_by
  end

  test "consumed_user_id 는 실 user 가 없어도 보존된다(FK 없음)" do
    merge = AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 123_456)

    assert_equal 123_456, merge.reload.consumed_user_id
    assert_nil User.find_by(id: 123_456)
  end

  test "active 스코프는 미되돌림(reversed_at IS NULL) 원장만 반환한다" do
    open_merge = AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 1)
    reversed = AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 2,
                                    reversed_at: Time.current, reversed_by_id: @performer.id)

    assert_includes AccountMerge.active, open_merge
    assert_not_includes AccountMerge.active, reversed
  end

  test "활성 병합에서 같은 consumed_user_id 는 1회만 소비된다(부분 유니크)" do
    AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 777)

    dup = AccountMerge.new(surviving_user_id: @survivor.id, consumed_user_id: 777)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end

  test "되돌린 병합은 같은 consumed_user_id 를 다시 소비할 수 있다(부분 유니크는 활성만)" do
    AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 888,
                         reversed_at: Time.current, reversed_by_id: @performer.id)

    again = AccountMerge.new(surviving_user_id: @survivor.id, consumed_user_id: 888)
    assert again.save, "되돌림 이후에는 같은 placeholder id 로 활성 원장을 만들 수 있어야 한다"
  end

  # --- reverse! 왕복(account_linking_seasons_plan §Phase 4) ---

  test "reverse! 왕복: 신원·평생·시즌 복원 + NEW 재생성 + FK 0 + 병합-후 활동 잔류" do
    ctx = merged_scenario
    old = ctx[:old].reload
    post_report = Report.create!(user: old, classroom: old.classroom, book_title: "병합후책", reviewed: true)

    result = ctx[:merge].reverse!(performed_by: @performer)
    assert result[:id_reused], "id·tuple 공백이라 원 id 재사용"

    old.reload
    assert_equal ctx[:old_classroom].id, old.classroom_id, "생존자 학급 복원"
    assert_equal "옛이름", old.name
    assert old.authenticate("oldpw1"), "작년 비번 복원"
    assert_equal "작년별", old.nickname
    assert_not old.ranking_opted_in?
    assert_equal 200, old.points, "평생 포인트 합산분 차감 복원"
    assert_equal 500, old.experience
    assert_equal ctx[:old_dex1].id, old.active_monster_id, "active_monster 복원"

    new = User.find_by(id: ctx[:new_id])
    assert new, "placeholder 재삽입(원 id 재사용)"
    assert_equal "새이름", new.name
    assert new.authenticate("newpw1"), "placeholder 비번 복원"
    assert_equal "올해별", new.nickname
    assert new.ranking_opted_in?
    assert_equal ctx[:new_classroom].id, new.classroom_id

    assert_equal 1, Report.where(user_id: new.id).count, "이동행 NEW 로 원복"
    assert Report.where(user_id: old.id).exists?(book_title: "옛책"), "작년 활동 생존자 유지"
    assert Report.exists?(post_report.id), "병합-후 활동은 생존자 잔류"
    assert_equal old.id, post_report.reload.user_id

    # 승격 복원 + 열등 dropped 불가역
    assert_equal species(1, 1).id, UserMonster.find(ctx[:old_dex1].id).monster_species_id, "OLD 승격 전 복원"
    new_dex1 = UserMonster.find_by(user_id: new.id, dex_no: 1)
    assert new_dex1 && new_dex1.monster_species_id == species(1, 2).id, "NEW 우월 개체 재생성"
    assert UserMonster.where(user_id: new.id, dex_no: 7).exists?, "이관 개체 원복"

    # 시즌 역연산: 병합-생성 생존자 현재 시즌 행은 0 되어 제거, 과거 시즌 불변, NEW 재생성
    assert_nil SeasonScore.find_by(user_id: old.id, academic_year: ctx[:current])
    assert_equal 100, SeasonScore.find_by(user_id: old.id, academic_year: ctx[:current] - 1).experience_earned
    assert_equal 30, SeasonScore.find_by(user_id: new.id, academic_year: ctx[:current]).experience_earned

    # dedup 삭제 vote 불가역
    assert_equal 1, ctx[:intro].reload.votes_count, "dedup 삭제 vote 는 복원 안 됨"
    assert_equal 0, BookIntroVote.where(user_id: new.id).count

    violations = ActiveRecord::Base.connection.select_all("PRAGMA foreign_key_check").to_a
    assert_empty violations, "reverse 후 FK 위반 없음: #{violations.inspect}"

    ctx[:merge].reload
    assert ctx[:merge].reversed_at
    assert_equal @performer.id, ctx[:merge].reversed_by_id
  end

  test "reverse! 새 id 리매핑: 원 id 점유 시 새 id 발급 + 자식 새 id 원복" do
    ctx = merged_scenario
    squatter = User.create!(id: ctx[:new_id], school: @school, classroom: ctx[:new_classroom],
                            name: "점유자", password: "password")

    result = ctx[:merge].reverse!(performed_by: @performer)

    assert_not result[:id_reused], "원 id 점유 시 새 id 발급"
    assert result[:requires_new_login]
    restored = User.find(result[:restored_new_id])
    assert_not_equal ctx[:new_id], restored.id
    assert_equal "새이름", restored.name
    assert_equal 1, Report.where(user_id: restored.id).count, "자식이 새 id 로 원복"
    assert User.exists?(squatter.id), "점유자 무사"

    violations = ActiveRecord::Base.connection.select_all("PRAGMA foreign_key_check").to_a
    assert_empty violations
  end

  test "이미 되돌린 병합 재되돌림은 ReversalError" do
    ctx = merged_scenario
    ctx[:merge].reverse!(performed_by: @performer)

    assert_raises(AccountMerge::ReversalError) { ctx[:merge].reverse!(performed_by: @performer) }
  end

  test "reverse! 시즌 역연산: OLD 가 원래 보유한 현재 학년도 행은 삭제 않고 이관분만 차감한다" do
    ctx = merged_scenario(old_current_experience: 15) # OLD 원보유 15 + NEW 이관 30 = 병합 후 45
    old = ctx[:old]

    ctx[:merge].reverse!(performed_by: @performer)

    row = SeasonScore.find_by(user_id: old.id, academic_year: ctx[:current])
    assert row, "원보유 현재 학년도 행은 병합-생성 행이 아니므로 삭제되지 않는다"
    assert_equal 15, row.experience_earned, "이관분(30)만 차감, 원 15 잔류(병합-후 누적 귀속 규칙)"
    assert_equal 15, row.points_earned

    restored_new = User.find_by(id: ctx[:new_id])
    assert_equal 30, SeasonScore.find_by(user_id: restored_new.id, academic_year: ctx[:current]).experience_earned, "NEW 시즌 재생성"
    assert_equal 100, SeasonScore.find_by(user_id: old.id, academic_year: ctx[:current] - 1).experience_earned, "과거 시즌 불변"

    violations = ActiveRecord::Base.connection.select_all("PRAGMA foreign_key_check").to_a
    assert_empty violations
  end

  test "동시 이중 되돌리기: 후행은 파괴적 복원 이전에 원자 클레임 0행 → clean ReversalError(500 아님)" do
    ctx = merged_scenario
    stale = AccountMerge.find(ctx[:merge].id) # 선행 커밋 전에 로드 → in-memory reversed_at nil

    ctx[:merge].reverse!(performed_by: @performer) # 선행 성공(DB reversed_at 스탬프)

    # 후행은 in-memory 가드는 통과하지만 원자 클레임(reversed_at IS NULL)이 0행 → ReversalError.
    error = assert_raises(AccountMerge::ReversalError) { stale.reverse!(performed_by: @performer) }
    assert_match "되돌", error.message

    # 후행이 파괴적 복원을 하지 않았으니(클레임이 선두) 무결성 보존.
    violations = ActiveRecord::Base.connection.select_all("PRAGMA foreign_key_check").to_a
    assert_empty violations
    assert_equal 1, User.where(id: ctx[:new_id]).count, "placeholder 이중 재삽입 없음"
  end

  private

  def species(dex_no, stage)
    MonsterSpecies.find_by!(dex_no: dex_no, stage: stage)
  end

  # 실제 MergeService 병합을 수행하고 되돌리기 검증에 필요한 앵커를 반환한다.
  def merged_scenario(old_current_experience: nil)
    seed_monster_species!
    seed_badges!
    current = Classroom.current_academic_year
    old_classroom = Classroom.create!(school: @school, grade: 3, class_no: 2, academic_year: current - 1)
    new_classroom = Classroom.create!(school: @school, grade: 4, class_no: 2, academic_year: current)
    old = User.create!(school: @school, classroom: old_classroom, name: "옛이름", password: "oldpw1")
    new = User.create!(school: @school, classroom: new_classroom, name: "새이름", password: "newpw1")
    old.update!(nickname: "작년별", ranking_opted_in: false)
    new.update!(nickname: "올해별", ranking_opted_in: true)
    author = User.create!(school: @school, classroom: new_classroom, name: "글쓴이R", password: "password")
    book = Book.create!(title: "역머지도서")

    Report.create!(user: old, classroom: old_classroom, book_title: "옛책", reviewed: true)
    Report.create!(user: new, classroom: new_classroom, book_title: "새책", reviewed: true)

    old_dex1 = UserMonster.create!(user: old, monster_species: species(1, 1), celebrated_at: 3.days.ago)
    UserMonster.create!(user: old, monster_species: species(2, 2))
    new_dex1 = UserMonster.create!(user: new, monster_species: species(1, 2)) # 승격 트리거
    UserMonster.create!(user: new, monster_species: species(7, 1))            # 이관
    old.update_columns(active_monster_id: old_dex1.id, points: 200, experience: 500)
    new.update_columns(points: 30, experience: 30)

    intro = BookIntro.create!(user: author, book: book, classroom: new_classroom, body: "소개 글입니다 재밌어요")
    BookIntroVote.create!(book_intro: intro, user: old)
    BookIntroVote.create!(book_intro: intro, user: new) # 충돌 → dedup drop(불가역)

    SeasonScore.create!(user: old, academic_year: current - 1, experience_earned: 100, points_earned: 50)
    SeasonScore.create!(user: new, academic_year: current, experience_earned: 30, points_earned: 30)
    # OLD 가 원래 현재 학년도 시즌 행을 보유한 분기(연중 연동 등). 병합이 NEW 분을 이 행에 더한다.
    if old_current_experience
      SeasonScore.create!(user: old, academic_year: current,
                          experience_earned: old_current_experience, points_earned: old_current_experience)
    end

    old.reload
    new.reload
    new_id = new.id
    result = Accounts::MergeService.new(old_account: old, new_account: new, performed_by: @performer).call
    assert result.ok?, "머지 선행 실패: #{result.error_code}"

    { old: old, old_classroom: old_classroom, new_classroom: new_classroom, new_id: new_id,
      merge: result.account_merge, book: book, intro: intro, old_dex1: old_dex1, new_dex1: new_dex1,
      current: current }
  end
end
