# 랭킹 집계(§13.5, P4.10). 학급/학년/학교/전국/챌린지/명예의 전당 순위를 계산한다.
# 컨트롤러를 얇게 유지하기 위한 순수 조회 서비스(부작용 없음).
#
# 시즌제(account_linking_seasons_plan §Phase 1): 읽기 플래그 `ranking_seasons` 가 켜지면
# 정렬 기준을 평생 `users.experience` 에서 현재 학년도 `season_scores.experience_earned` 로
# 전환한다(매 학년도 0 재출발). 플래그 off(기본)면 평생 experience 폴백으로 완전 무변경.
# 시즌 조인은 항상 현재 소속(users.classroom_id/school_id)으로 그룹핑하며 스냅샷 컬럼은 쓰지 않는다.
class RankingBoard
  # 집계 결과 한 줄. subject = 순위 주체(User/Classroom/School), score = 정렬 기준값.
  Entry = Struct.new(:subject, :score, :meta, keyword_init: true)

  def initialize(user)
    @user = user
  end

  # 학급 학생 순위(내림차순). 학생만 대상.
  # 시즌 on: 현재 학년도 시즌 경험치(season_experience) 순. off: 평생 누적 경험치 순.
  def class_ranking
    classroom = @user.classroom
    return [] unless classroom

    students = classroom.users.where(role: :student)
    return students.order(experience: :desc, name: :asc).to_a unless seasons_enabled?

    students
      .joins(season_join_sql)
      .select("users.*", "COALESCE(season_scores.experience_earned, 0) AS season_experience")
      .order(Arel.sql("season_experience DESC, users.name ASC"))
      .to_a
  end

  # 포디움 Top3(학급 순위 상위 3명).
  def podium
    class_ranking.first(3)
  end

  # 뷰어 학교 + 같은 학년(현재 소속) 학생 개인 순위(신규).
  # 시즌 on: 현재 학년도 시즌 경험치 순. off: 평생 경험치 순.
  def grade_ranking
    classroom = @user.classroom
    school = @user.school
    return [] unless classroom && school

    students = User.where(role: :student, school_id: school.id)
                   .joins(:classroom)
                   .where(classrooms: { grade: classroom.grade })
    return students.order(experience: :desc, name: :asc).to_a unless seasons_enabled?

    students
      .joins(season_join_sql)
      .select("users.*", "COALESCE(season_scores.experience_earned, 0) AS season_experience")
      .order(Arel.sql("season_experience DESC, users.name ASC"))
      .to_a
  end

  # 학교 내 학급 집계(학생 경험치 합) 순위.
  # 학급별 경험치·포인트 합과 인원수를 한 번의 그룹 집계로 읽는다(P3.1).
  # 정렬 기준은 감소하지 않는 경험치 합이고, 보유 포인트 합은 함께 표시할 메타데이터로 제공한다.
  # 학생 없는 학급도 합계 0·평균 0 으로 포함한다.
  # 시즌 on: 현재 소속 classroom_id 로 group + SUM(season_scores.experience_earned). off: 평생 experience 합.
  def school_ranking
    school = @user.school
    return [] unless school

    classrooms = school.classrooms.to_a
    classroom_ids = classrooms.map(&:id)
    aggregates = classroom_experience_aggregates(classroom_ids)

    classrooms.map do |classroom|
      total, points, count = aggregates.fetch(classroom.id, [ 0, 0, 0 ])
      avg = count.zero? ? 0 : (total.to_f / count).round(1)
      Entry.new(subject: classroom, score: total, meta: { avg: avg, points: points })
    end.sort_by { |entry| -entry.score }
  end

  # 전국 학교 집계(소속 학생 경험치 합) 순위. Top N(기본 100) 상한 + 학생 0명 학교 제외(계획 §2.3).
  # 6,300교 전량 struct 생성·정렬·렌더를 막는다. 상수 쿼리 2개(그룹 SUM + 필요한 학교만 로드)로
  # 규모에 무관하다. Top N 밖이면 뷰어 본인 학교 순위를 별도 행(meta[:self])으로 덧붙여 소형·신규
  # 학교의 동기부여를 보존한다. 학교 미소속(school_id nil) 학생 집계는 순위에서 제외한다.
  # 시즌 on: 현재 소속 school_id 로 group + SUM(season_scores.experience_earned). off: 평생 experience 합.
  def nation_ranking(limit: 100)
    aggregates = school_experience_aggregates
    totals = aggregates.to_h { |school_id, experience, _points| [ school_id, experience ] }
    point_totals = aggregates.to_h { |school_id, _experience, points| [ school_id, points ] }
    totals.delete(nil)
    point_totals.delete(nil)
    return [] if totals.empty?

    ranked_ids = totals.sort_by { |school_id, score| [ -score, school_id ] }.map(&:first)

    own_id = @user&.school_id
    own_index = own_id ? ranked_ids.index(own_id) : nil

    needed_ids = ranked_ids.first(limit)
    needed_ids += [ own_id ] if own_index && own_index >= limit # 본인 학교가 Top N 밖이면 함께 로드
    schools_by_id = School.where(id: needed_ids).index_by(&:id)

    entries = ranked_ids.first(limit).each_with_index.filter_map do |school_id, index|
      school = schools_by_id[school_id]
      Entry.new(
        subject: school,
        score: totals[school_id],
        meta: { rank: index + 1, points: point_totals[school_id] }
      ) if school
    end

    if own_index && own_index >= limit && (own = schools_by_id[own_id])
      entries << Entry.new(
        subject: own,
        score: totals[own_id],
        meta: { rank: own_index + 1, self: true, points: point_totals[own_id] }
      )
    end

    entries
  end

  # 챌린지 참여 순위(참여 독후감 수 기준).
  def challenge_ranking(challenge)
    return [] unless challenge

    counts = Report.where(challenge_id: challenge.id).group(:user_id).count
    users = User.where(id: counts.keys).index_by(&:id)
    # users[user_id] 가 nil(유저 삭제/스코프 제외)이면 subject 가 nil 인 Entry 가 만들어져
    # 뷰의 entry.subject.name 에서 크래시한다 → nil subject 는 건너뛴다(P2.7).
    counts.filter_map do |user_id, count|
      subject = users[user_id]
      Entry.new(subject: subject, score: count, meta: {}) if subject
    end.sort_by { |entry| -entry.score }
  end

  # 명예의 전당 — 성장 신호 = 도감 완성도(보유 라인) + 진화 성취(완전형 수).
  # 대상 범위는 종전과 동일하게 전교(전체 학생) — 스코프 불변. 학생당 2쿼리(도감/완전형)를
  # 두 번의 그룹 집계로 접어 학생 수에 무관한 상수 쿼리로 만든다(P3.1). user_monsters 는
  # 학생에게만 달리므로 그룹 결과를 학생별로 조회해도 출력은 종전 per-student 계산과 동일하다.
  def hall_of_fame(limit: 10)
    students = User.where(role: :student).includes(:active_monster).to_a
    dex_counts = UserMonster.group(:user_id).distinct.count(:dex_no)
    complete_counts = UserMonster.joins(:monster_species)
                                 .where(monster_species: { stage: MonsterSpecies::MAX_STAGE })
                                 .group(:user_id).count

    students.map do |student|
      dex = dex_counts[student.id] || 0
      complete = complete_counts[student.id] || 0
      Entry.new(subject: student, score: dex + complete, meta: { dex: dex, complete: complete })
    end.select { |entry| entry.score.positive? }
        .sort_by { |entry| [ -entry.score, entry.subject.name ] }
        .first(limit)
  end

  private

  # 읽기 플래그 게이트. off(기본)면 모든 시즌 정렬 경로가 평생 experience 폴백으로 돌아간다.
  # scope 는 뷰어의 학급 — 파일럿→확대 롤아웃과 학급 단위 격리를 지원한다.
  def seasons_enabled?
    return @seasons_enabled if defined?(@seasons_enabled)

    @seasons_enabled = AppSetting.feature_enabled?("ranking_seasons", scope: @user&.classroom, default: false)
  end

  # 현재 학년도 season_scores 를 라이브 멤버십(users)에 붙이는 LEFT JOIN 절.
  # [academic_year, user_id] 유니크 인덱스를 타며, 현재 학년도 상수로 한정한다.
  def season_join_sql
    <<~SQL.squish
      LEFT JOIN season_scores
        ON season_scores.user_id = users.id
        AND season_scores.academic_year = #{current_year.to_i}
    SQL
  end

  def current_year
    @current_year ||= Classroom.current_academic_year
  end

  # 학교 순위용 학급별 (경험치 합, 포인트 합, 인원수) 집계.
  def classroom_experience_aggregates(classroom_ids)
    students = User.where(role: :student, classroom_id: classroom_ids)
    if seasons_enabled?
      students.joins(season_join_sql)
              .group(Arel.sql("users.classroom_id"))
              .pluck(Arel.sql("users.classroom_id"),
                     Arel.sql("SUM(COALESCE(season_scores.experience_earned, 0))"),
                     Arel.sql("SUM(COALESCE(season_scores.points_earned, 0))"),
                     Arel.sql("COUNT(users.id)"))
              .to_h { |classroom_id, experience, points, count| [ classroom_id, [ experience.to_i, points.to_i, count ] ] }
    else
      students.group(:classroom_id)
              .pluck(:classroom_id, Arel.sql("SUM(experience)"), Arel.sql("SUM(points)"), Arel.sql("COUNT(*)"))
              .to_h { |classroom_id, experience, points, count| [ classroom_id, [ experience, points, count ] ] }
    end
  end

  # 전국 순위용 학교별 [school_id, 경험치 합, 포인트 합] 집계.
  def school_experience_aggregates
    if seasons_enabled?
      User.joins(:school).joins(season_join_sql)
          .where(role: :student, schools: { active: true })
          .group(Arel.sql("users.school_id"))
          .pluck(Arel.sql("users.school_id"),
                 Arel.sql("SUM(COALESCE(season_scores.experience_earned, 0))"),
                 Arel.sql("SUM(COALESCE(season_scores.points_earned, 0))"))
          .map { |school_id, experience, points| [ school_id, experience.to_i, points.to_i ] }
    else
      User.joins(:school)
          .where(role: :student, schools: { active: true })
          .group(:school_id)
          .pluck(:school_id, Arel.sql("SUM(experience)"), Arel.sql("SUM(points)"))
    end
  end
end
