require "test_helper"

# 계정 연동(MERGE) 코어 전수 테스트(account_linking_seasons_plan §Phase 2 / §3 수용기준 / §4).
# FK 무결성·테이블별 count parity·counter parity(표준5/커스텀)·user_monsters in-place 승격·
# active_monster 불변·book_intros/sequels 이관·조용한 FK 보존·시즌 sum-and-delete·조건부 claim
# 동시성·가드 위반 롤백·hide 미재평가를 커버한다.
class Accounts::MergeServiceTest < ActiveSupport::TestCase
  setup do
    seed_monster_species!
    seed_badges!
    @current = Classroom.current_academic_year
    @school = School.create!(name: "연동초등학교")
    @old_classroom = Classroom.create!(school: @school, grade: 3, class_no: 1, academic_year: @current - 1)
    @new_classroom = Classroom.create!(school: @school, grade: 4, class_no: 1, academic_year: @current)

    @old = User.create!(school: @school, classroom: @old_classroom, name: "작년이름", password: "password")
    @new = User.create!(school: @school, classroom: @new_classroom, name: "올해이름", password: "password")
    @teacher = User.create!(school: @school, classroom: @new_classroom, name: "담임", role: :teacher,
                            password: "password", email: "teacher@example.com")
    @author = User.create!(school: @school, classroom: @new_classroom, name: "글쓴이", password: "password")
    @book = Book.create!(title: "연동테스트도서")
  end

  # --- 정상 병합(전체 시나리오) ---

  test "FK 무결성: 병합 후 foreign_key_check 0행" do
    populate!
    assert run_merge.ok?

    violations = ActiveRecord::Base.connection.select_all("PRAGMA foreign_key_check").to_a
    assert_empty violations, "병합 후 FK 위반이 없어야 한다: #{violations.inspect}"
  end

  test "placeholder 는 사라지고 생존자가 현재 학년도 신원을 승계한다" do
    populate!
    digest = @new.password_digest
    assert run_merge.ok?

    assert_not User.exists?(@new.id), "placeholder 는 삭제된다"
    @old.reload
    assert_equal @new_classroom.id, @old.classroom_id
    assert_equal @school.id, @old.school_id
    assert_equal "올해이름", @old.name
    assert_equal digest, @old.password_digest
  end

  test "테이블별 count parity: after(survivor) == before(old)+before(new)-dropped" do
    populate!
    before = {
      reports: [ count_for("reports", "user_id", @old.id), count_for("reports", "user_id", @new.id) ],
      user_badges: [ count_for("user_badges", "user_id", @old.id), count_for("user_badges", "user_id", @new.id) ],
      cheers: [ count_for("cheers", "user_id", @old.id), count_for("cheers", "user_id", @new.id) ],
      user_monsters: [ count_for("user_monsters", "user_id", @old.id), count_for("user_monsters", "user_id", @new.id) ],
      game_plays: [ count_for("game_plays", "user_id", @old.id), count_for("game_plays", "user_id", @new.id) ]
    }

    merge = run_merge.account_merge
    dropped = merge.snapshot["dropped"]

    assert_equal before[:reports].sum, count_for("reports", "user_id", @old.id) # 단순 이관, dropped 0
    assert_parity("user_badges", before[:user_badges], dropped["user_badges"].size)
    assert_parity("cheers", before[:cheers], dropped["cheers"].size)
    assert_parity("game_plays", before[:game_plays], dropped["game_plays"].size)
    # user_monsters: dropped = 열등/중복 NEW 행(dropped_new)
    assert_equal before[:user_monsters].sum - dropped["user_monsters"].size,
                 count_for("user_monsters", "user_id", @old.id)
  end

  test "counter parity: 표준 5종 reset_counters 로 저장값 == 연관 count" do
    populate!
    assert run_merge.ok?

    assert_equal @book_intro.book_intro_votes.count, @book_intro.reload.votes_count
    assert_equal 1, @book_intro.votes_count, "충돌 삭제로 2 → 1 재집계"

    assert_equal @book_sequel.book_sequel_votes.count, @book_sequel.reload.votes_count
    assert_equal 1, @book_sequel.votes_count

    assert_equal @forum_post.forum_post_likes.count, @forum_post.reload.likes_count
    assert_equal 1, @forum_post.likes_count
    assert_equal @forum_post.forum_post_reports.count, @forum_post.reports_count
    assert_equal 1, @forum_post.reports_count

    assert_equal @quiz.quiz_reports.count, @quiz.reload.reports_count
    assert_equal 1, @quiz.reports_count
  end

  test "counter parity: cheers 는 report.cheers_count == board_post.cheers.count 커스텀 재집계" do
    populate!
    assert_equal 2, @shared_report.reload.cheers_count, "병합 전 2인 응원"
    assert run_merge.ok?

    assert_equal @board_post.cheers.count, @shared_report.reload.cheers_count
    assert_equal 1, @shared_report.cheers_count, "충돌 삭제로 2 → 1"
  end

  test "user_monsters in-place 승격: OLD 행 id 불변·species 승격·celebrated_at 보존·유니크 유지" do
    populate!
    old_dex1_id = @old_dex1.id
    celebrated = @old_dex1.celebrated_at
    superior_species_id = @new_dex1.monster_species_id
    assert run_merge.ok?

    promoted = UserMonster.find(old_dex1_id) # id 불변
    assert_equal @old.id, promoted.user_id
    assert_equal superior_species_id, promoted.monster_species_id, "NEW 우월 species 로 제자리 승격"
    assert_equal celebrated.to_i, promoted.celebrated_at.to_i, "celebrated_at 보존"
    assert_not UserMonster.exists?(@new_dex1.id), "승격 후 NEW 우월행은 삭제"

    dex_nos = UserMonster.where(user_id: @old.id).pluck(:dex_no)
    assert_equal dex_nos.uniq.sort, dex_nos.sort, "[user_id, dex_no] 유니크 유지"
  end

  test "active_monster 유효성: NEW 우월 승격으로도 survivor.active_monster_id 불변·유효" do
    populate!
    active_id = @old.active_monster_id
    assert_equal @old_dex1.id, active_id
    superior_species_id = @new_dex1.monster_species_id
    assert run_merge.ok?

    @old.reload
    assert_equal active_id, @old.active_monster_id, "active_monster_id(=OLD dex1 행 id) 불변"
    assert UserMonster.exists?(@old.active_monster_id), "삭제행 미참조"
    assert_equal superior_species_id, @old.active_monster.monster_species_id, "그 행 species 승격"
  end

  test "OLD 우월/동률 충돌은 NEW 행만 버리고 OLD species 를 유지한다" do
    populate!
    old_dex2_species = @old_dex2.monster_species_id
    assert run_merge.ok?

    kept = UserMonster.find(@old_dex2.id)
    assert_equal old_dex2_species, kept.monster_species_id, "OLD 우월이면 species 유지"
    assert_not UserMonster.exists?(@new_dex2.id), "열등 NEW 행 삭제"
  end

  test "book_intros/book_sequels 보유 placeholder 도 delete_all abort 없이 이관된다" do
    populate!
    intro_id = @new_intro.id
    sequel_id = @new_sequel.id
    assert run_merge.ok?, "user_id NOT NULL+RESTRICT 이관 누락 시 placeholder 삭제가 abort 된다"

    assert_equal @old.id, BookIntro.find(intro_id).user_id
    assert_equal @old.id, BookSequel.find(sequel_id).user_id
  end

  test "조용한 FK 보존: quiz_contributions(cascade)·recommendation_imports(nullify) count 보존" do
    populate!
    contribution_id = @new_contribution.id
    import_id = @new_import.id
    assert run_merge.ok?

    assert_equal @old.id, QuizContribution.find(contribution_id).user_id, "cascade 지만 이관으로 보존"
    assert_equal @old.id, RecommendationImport.find(import_id).imported_by_id, "nullify 대신 이관으로 귀속 보존"
  end

  test "시즌 sum-and-delete: NEW 시즌 행 OLD 합산·삭제, [academic_year,user_id] 유니크 유지" do
    populate!
    assert run_merge.ok?

    current_row = SeasonScore.find_by(user_id: @old.id, academic_year: @current)
    assert_equal 40, current_row.experience_earned, "OLD 10 + NEW 30"
    assert_equal 40, current_row.points_earned

    past_row = SeasonScore.find_by(user_id: @old.id, academic_year: @current - 1)
    assert_equal 100, past_row.experience_earned, "과거 시즌은 불변"

    assert_empty SeasonScore.where(user_id: @new.id), "NEW 시즌 행 전량 삭제"
    identities = SeasonScore.where(user_id: @old.id).pluck(:academic_year)
    assert_equal identities.uniq.sort, identities.sort
  end

  test "평생 자산은 합산 이월된다(experience/points)" do
    populate!
    assert run_merge.ok?

    @old.reload
    assert_equal 230, @old.points, "OLD 200 + NEW 30"
    assert_equal 530, @old.experience, "OLD 500 + NEW 30"
  end

  test "hide 플래그 미재평가: 신고자 2→1 이 되어도 sticky 유지" do
    populate!
    @forum_post.update_columns(hidden: true)
    @quiz.update_columns(reported: true)
    assert run_merge.ok?

    assert @forum_post.reload.hidden, "counter 만 재집계, hidden 플래그는 자동 해제하지 않는다"
    assert_equal 1, @forum_post.reports_count
    assert @quiz.reload.reported, "quiz.reported 도 sticky"
    assert_equal 1, @quiz.reports_count
  end

  test "감사 원장에 이동 요약·수행자·소속 전이가 기록된다" do
    populate!
    merge = run_merge.account_merge

    assert_equal @old.id, merge.surviving_user_id
    assert_equal @new.id, merge.consumed_user_id
    assert_equal @teacher.id, merge.performed_by_id
    assert_equal User.roles[@teacher.role], merge.performed_by_role
    assert_equal @old_classroom.id, merge.from_classroom_id
    assert_equal @new_classroom.id, merge.to_classroom_id
    assert_equal 3, merge.moved_counts["reports"], "이동 요약은 placeholder(NEW)에서 옮겨온 행 수"
  end

  # --- 조건부 claim 동시성 ---

  test "조건부 claim 동시성: 선행 커밋 후 후행 claim affected 0 → 롤백(후행 NEW 보존)" do
    old_a = User.find(@old.id)
    old_b = User.find(@old.id) # 선행 커밋 전에 pre-merge tuple 로드
    new_b = User.create!(school: @school, classroom: @new_classroom, name: "다른올해", password: "password")

    result_a = Accounts::MergeService.new(old_account: old_a, new_account: @new, performed_by: @teacher).call
    assert result_a.ok?

    result_b = Accounts::MergeService.new(old_account: old_b, new_account: new_b, performed_by: @teacher).call
    assert_not result_b.ok?, "같은 생존자를 두 번 claim 할 수 없다"
    assert_equal :claim_conflict, result_b.error_code
    assert User.exists?(new_b.id), "후행 롤백으로 NEW 삭제도 원복된다"
  end

  # --- 가드 위반 롤백 ---

  test "가드: 비학생은 병합 거부" do
    result = Accounts::MergeService.new(old_account: @teacher, new_account: @new, performed_by: @teacher).call
    assert_not result.ok?
    assert_equal :not_students, result.error_code
  end

  test "가드: 같은 계정 병합 거부" do
    result = Accounts::MergeService.new(old_account: @old, new_account: @old, performed_by: @teacher).call
    assert_not result.ok?
    assert_equal :same_account, result.error_code
  end

  test "가드: 현재 학년도 계정을 생존자로 지정하면 거부(invalid_source)" do
    new2 = User.create!(school: @school, classroom: @new_classroom, name: "또다른올해", password: "password")
    result = Accounts::MergeService.new(old_account: @new, new_account: new2, performed_by: @teacher).call
    assert_not result.ok?
    assert_equal :invalid_source, result.error_code
  end

  test "가드: placeholder 가 현재 학년도가 아니면 거부(invalid_target)" do
    old2 = User.create!(school: @school, classroom: @old_classroom, name: "또다른작년", password: "password")
    result = Accounts::MergeService.new(old_account: @old, new_account: old2, performed_by: @teacher).call
    assert_not result.ok?
    assert_equal :invalid_target, result.error_code
  end

  test "가드: 정지된 계정이면 거부(suspended)" do
    @old.update_columns(suspended: true)
    result = Accounts::MergeService.new(old_account: @old, new_account: @new, performed_by: @teacher).call
    assert_not result.ok?
    assert_equal :suspended, result.error_code
  end

  test "가드 위반은 부작용 없이 완전 롤백된다" do
    populate!
    @old.update_columns(suspended: true)
    reports_before = count_for("reports", "user_id", @new.id)

    result = Accounts::MergeService.new(old_account: @old, new_account: @new, performed_by: @teacher).call
    assert_not result.ok?

    assert User.exists?(@new.id), "placeholder 미삭제"
    assert_equal reports_before, count_for("reports", "user_id", @new.id), "NEW 자식행 미이관"
    assert_equal 0, AccountMerge.count, "감사 원장 미기록"
  end

  # --- 리뷰 fix: RecordNotUnique 우아한 처리 + 커밋 후 멱등 ---

  test "이미 소비된 placeholder 재소비 시도는 :consumed_conflict 로 우아하게 롤백된다" do
    populate!
    # 같은 placeholder(@new)를 소비한 활성 병합이 이미 있는 상태(경합/재시도) — write_audit! 의
    # 활성 consumed 부분유니크가 두 번째 소비를 차단한다. (지배적 same-OLD 경합은 claim 이 먼저 잡음.)
    AccountMerge.create!(surviving_user_id: @teacher.id, consumed_user_id: @new.id)
    old_classroom_before = @old.classroom_id
    new_reports_before = count_for("reports", "user_id", @new.id)

    result = run_merge

    assert_not result.ok?
    assert_equal :consumed_conflict, result.error_code
    assert User.exists?(@new.id), "placeholder 미삭제(완전 롤백)"
    assert_equal old_classroom_before, @old.reload.classroom_id, "생존자 미claim"
    assert_equal new_reports_before, count_for("reports", "user_id", @new.id), "자식행 미이동"
    assert_equal 1, AccountMerge.count, "새 감사 원장 미기록(사전 시드 1건만)"
  end

  test "커밋 후 사이드이펙트는 survivor reload + 후크만, 포인트 재적립 없음(멱등)" do
    populate!
    service = Accounts::MergeService.new(old_account: @old, new_account: @new, performed_by: @teacher)
    result = service.call
    assert result.ok?

    survivor = result.surviving_user
    service.run_post_commit_side_effects!(survivor)
    assert_equal 230, survivor.points, "합산 포인트 유지(재적립 없음)"
    assert_equal 530, survivor.experience

    service.run_post_commit_side_effects!(survivor) # 재호출 멱등
    assert_equal 230, survivor.reload.points
    assert_equal 530, survivor.experience
  end

  private

  def run_merge
    Accounts::MergeService.new(old_account: @old, new_account: @new, performed_by: @teacher).call
  end

  def count_for(table, column, user_id)
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table} WHERE #{column} = #{user_id.to_i}").to_i
  end

  def assert_parity(table, before_pair, dropped_count)
    expected = before_pair[0] + before_pair[1] - dropped_count
    assert_equal expected, count_for(table, "user_id", @old.id),
                 "#{table}: after(#{count_for(table, 'user_id', @old.id)}) == #{before_pair[0]}+#{before_pair[1]}-#{dropped_count}"
  end

  def species(dex_no, stage)
    MonsterSpecies.find_by!(dex_no: dex_no, stage: stage)
  end

  # 병합 전 풍부한 자식행(충돌·비충돌)을 심는다. dedup·counter·승격·시즌·평생 전수 경로를 만든다.
  def populate!
    # --- reports(단순 이관) ---
    2.times { |i| Report.create!(user: @old, classroom: @old_classroom, book_title: "작년책#{i}", reviewed: true) }
    3.times { |i| Report.create!(user: @new, classroom: @new_classroom, book_title: "올해책#{i}", reviewed: true) }

    # --- user_monsters(in-place 승격 / 열등 드롭 / 이관) ---
    @old_dex1 = UserMonster.create!(user: @old, monster_species: species(1, 1), celebrated_at: 2.days.ago)
    @old_dex2 = UserMonster.create!(user: @old, monster_species: species(2, 2))
    UserMonster.create!(user: @old, monster_species: species(5, 1))
    @new_dex1 = UserMonster.create!(user: @new, monster_species: species(1, 2)) # OLD dex1 승격 트리거
    @new_dex2 = UserMonster.create!(user: @new, monster_species: species(2, 1)) # 열등 → 드롭
    UserMonster.create!(user: @new, monster_species: species(7, 1))            # 비충돌 → 이관
    @old.update_columns(active_monster_id: @old_dex1.id)

    # --- user_badges(dedup) ---
    UserBadge.create!(user: @old, badge: badge("first"))
    UserBadge.create!(user: @new, badge: badge("first")) # 충돌 → 드롭
    UserBadge.create!(user: @new, badge: badge("three")) # 이관

    # --- cheers(커스텀 counter) ---
    @shared_report = Report.create!(user: @author, classroom: @new_classroom, book_title: "우수작", reviewed: true, shared: true)
    @board_post = BoardPost.create!(report: @shared_report)
    Cheer.create!(board_post: @board_post, user: @old)
    Cheer.create!(board_post: @board_post, user: @new) # 충돌 → 드롭
    @shared_report.update_columns(cheers_count: 2)

    # --- book_intro_votes / book_intros ---
    @book_intro = BookIntro.create!(user: @author, book: @book, classroom: @new_classroom, body: "책 소개 글입니다 재미있어요")
    BookIntroVote.create!(book_intro: @book_intro, user: @old)
    BookIntroVote.create!(book_intro: @book_intro, user: @new) # 충돌 → 드롭, votes_count 2→1
    @new_intro = BookIntro.create!(user: @new, book: @book, classroom: @new_classroom, body: "올해 학생 소개 글입니다") # 단순 이관

    # --- book_sequel_votes / book_sequels ---
    @book_sequel = BookSequel.create!(user: @author, book: @book, classroom: @new_classroom, body: "뒷이야기 글입니다 이어집니다")
    BookSequelVote.create!(book_sequel: @book_sequel, user: @old)
    BookSequelVote.create!(book_sequel: @book_sequel, user: @new) # 충돌 → 드롭
    @new_sequel = BookSequel.create!(user: @new, book: @book, classroom: @new_classroom, body: "올해 학생 뒷이야기입니다") # 이관

    # --- forum(likes·reports dedup + 단순 이관) ---
    @topic = Topic.create!(classroom: @new_classroom, scope: :classroom, title: "우리반 토론방")
    @forum_post = ForumPost.create!(topic: @topic, user: @author, text: "재미있는 토론이에요")
    ForumPostLike.create!(forum_post: @forum_post, user: @old)
    ForumPostLike.create!(forum_post: @forum_post, user: @new) # 충돌 → 드롭
    ForumPostReport.create!(forum_post: @forum_post, user: @old)
    ForumPostReport.create!(forum_post: @forum_post, user: @new) # 충돌 → 드롭
    ForumPost.create!(topic: @topic, user: @old, text: "작년 학생 토론 글")  # 단순 이관
    ForumPost.create!(topic: @topic, user: @new, text: "올해 학생 토론 글")  # 단순 이관

    # --- quiz_reports / quiz_attempts ---
    @quiz = Quiz.create!(title: "독서 퀴즈", created_by: @teacher, origin: :system, scope: :global)
    QuizReport.create!(quiz: @quiz, user: @old)
    QuizReport.create!(quiz: @quiz, user: @new) # 충돌 → 드롭
    QuizAttempt.create!(quiz: @quiz, user: @old, score: 1, played_at: Time.current)
    QuizAttempt.create!(quiz: @quiz, user: @new, score: 1, played_at: Time.current) # 단순 이관

    # --- mission_participations(dedup) ---
    m1 = create_mission("미션1")
    m2 = create_mission("미션2")
    MissionParticipation.create!(mission: m1, user: @old)
    MissionParticipation.create!(mission: m1, user: @new) # 충돌 → 드롭
    MissionParticipation.create!(mission: m2, user: @new) # 이관

    # --- game_plays(부분 유니크 2종) ---
    today = Date.current
    GamePlay.create!(user: @old, game_type: :quiz, book: @book, played_on: today)
    GamePlay.create!(user: @old, game_type: :whoami, book: @book, played_on: today)
    GamePlay.create!(user: @old, game_type: :quiz, book: nil, played_on: today)
    GamePlay.create!(user: @new, game_type: :quiz, book: @book, played_on: today) # 충돌(book 있음) → 드롭
    GamePlay.create!(user: @new, game_type: :book, book: @book, played_on: today) # 비충돌 → 이관
    GamePlay.create!(user: @new, game_type: :quiz, book: nil, played_on: today)   # 충돌(book NULL) → 드롭

    # --- stickers(by_user_id 단순 이관) ---
    Sticker.create!(report: @shared_report, by_user: @new, emoji: "👍", position: 1)

    # --- quiz_contributions(cascade) / recommendation_imports(nullify) 조용한 FK 보존 ---
    @new_contribution = QuizContribution.create!(
      user: @new, book: @book, classroom: @new_classroom, content_axis: :mcq, band: :g34,
      payload: { "prompt" => "이 책의 주제는?", "choices" => %w[가 나 다 라], "answer_index" => 0, "explanation" => "해설입니다" }
    )
    @new_import = RecommendationImport.create!(
      imported_by: @new, filename: "rec.xlsx", file_digest: "digest-#{SecureRandom.hex(8)}",
      imported_at: Time.current, item_count: 0
    )

    # --- 시즌(sum-and-delete) ---
    SeasonScore.create!(user: @old, academic_year: @current - 1, experience_earned: 100, points_earned: 50)
    SeasonScore.create!(user: @old, academic_year: @current, experience_earned: 10, points_earned: 10)
    SeasonScore.create!(user: @new, academic_year: @current, experience_earned: 30, points_earned: 30)

    # --- 평생 자산 ---
    @old.update_columns(points: 200, experience: 500)
    @new.update_columns(points: 30, experience: 30)
    @old.reload
    @new.reload
  end

  def badge(key)
    Badge.find_by!(key: key)
  end

  def create_mission(title)
    Mission.create!(classroom: @new_classroom, created_by: @teacher, title: title,
                    start_date: Date.current, end_date: Date.current + 7, reward_points: 0)
  end
end
