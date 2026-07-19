# 랭킹 집계(§13.5, P4.10). 학급/학교/전국/챌린지/명예의 전당 순위를 계산한다.
# 컨트롤러를 얇게 유지하기 위한 순수 조회 서비스(부작용 없음).
class RankingBoard
  # 집계 결과 한 줄. subject = 순위 주체(User/Classroom/School), score = 정렬 기준값.
  Entry = Struct.new(:subject, :score, :meta, keyword_init: true)

  def initialize(user)
    @user = user
  end

  # 학급 학생 포인트 순위(내림차순). 학생만 대상.
  def class_ranking
    classroom = @user.classroom
    return [] unless classroom

    classroom.users.where(role: :student).order(points: :desc, name: :asc).to_a
  end

  # 포디움 Top3(학급 순위 상위 3명).
  def podium
    class_ranking.first(3)
  end

  # 학교 내 학급 집계(학생 포인트 합) 순위.
  # 학급별 포인트·경험치 합과 인원수를 한 번의 그룹 집계로 읽는다(P3.1).
  # 정렬 기준은 기존 포인트 합을 유지하고, 경험치 합은 함께 표시할 메타데이터로 제공한다.
  # 학생 없는 학급도 합계 0·평균 0 으로 포함한다.
  def school_ranking
    school = @user.school
    return [] unless school

    classrooms = school.classrooms.to_a
    classroom_ids = classrooms.map(&:id)
    students = User.where(role: :student, classroom_id: classroom_ids)
    aggregates = students.group(:classroom_id)
                         .pluck(:classroom_id, Arel.sql("SUM(points)"), Arel.sql("SUM(experience)"), Arel.sql("COUNT(*)"))
                         .to_h { |classroom_id, points, experience, count| [ classroom_id, [ points, experience, count ] ] }

    classrooms.map do |classroom|
      total, experience, count = aggregates.fetch(classroom.id, [ 0, 0, 0 ])
      avg = count.zero? ? 0 : (total.to_f / count).round(1)
      Entry.new(subject: classroom, score: total, meta: { avg: avg, experience: experience })
    end.sort_by { |entry| -entry.score }
  end

  # 전국 학교 집계(소속 학생 포인트 합) 순위. Top N(기본 100) 상한 + 학생 0명 학교 제외(계획 §2.3).
  # 6,300교 전량 struct 생성·정렬·렌더를 막는다. 상수 쿼리 2개(그룹 SUM + 필요한 학교만 로드)로
  # 규모에 무관하다. Top N 밖이면 뷰어 본인 학교 순위를 별도 행(meta[:self])으로 덧붙여 소형·신규
  # 학교의 동기부여를 보존한다. 학교 미소속(school_id nil) 학생 집계는 순위에서 제외한다.
  def nation_ranking(limit: 100)
    aggregates = User.joins(:school)
                     .where(role: :student, schools: { active: true })
                     .group(:school_id)
                     .pluck(:school_id, Arel.sql("SUM(points)"), Arel.sql("SUM(experience)"))
    totals = aggregates.to_h { |school_id, points, _experience| [ school_id, points ] }
    experiences = aggregates.to_h { |school_id, _points, experience| [ school_id, experience ] }
    totals.delete(nil)
    experiences.delete(nil)
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
        meta: { rank: index + 1, experience: experiences[school_id] }
      ) if school
    end

    if own_index && own_index >= limit && (own = schools_by_id[own_id])
      entries << Entry.new(
        subject: own,
        score: totals[own_id],
        meta: { rank: own_index + 1, self: true, experience: experiences[own_id] }
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
end
