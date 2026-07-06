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
  def school_ranking
    school = @user.school
    return [] unless school

    school.classrooms.map do |classroom|
      Entry.new(subject: classroom, score: classroom_total(classroom), meta: { avg: classroom_avg(classroom) })
    end.sort_by { |entry| -entry.score }
  end

  # 전국 학교 집계(소속 학생 포인트 합) 순위.
  def nation_ranking
    School.all.map do |school|
      Entry.new(subject: school, score: school.users.where(role: :student).sum(:points), meta: {})
    end.sort_by { |entry| -entry.score }
  end

  # 챌린지 참여 순위(참여 독후감 수 기준).
  def challenge_ranking(challenge)
    return [] unless challenge

    counts = Report.where(challenge_id: challenge.id).group(:user_id).count
    users = User.where(id: counts.keys).index_by(&:id)
    counts.map { |user_id, count| Entry.new(subject: users[user_id], score: count, meta: {}) }
          .sort_by { |entry| -entry.score }
  end

  # 명예의 전당 — 성장 신호 = 도감 완성도(보유 라인) + 진화 성취(완전형 수).
  def hall_of_fame(limit: 10)
    User.where(role: :student).includes(:active_monster).map do |student|
      dex = student.user_monsters.distinct.count(:dex_no)
      complete = complete_form_count(student)
      Entry.new(subject: student, score: dex + complete, meta: { dex: dex, complete: complete })
    end.select { |entry| entry.score.positive? }
        .sort_by { |entry| [ -entry.score, entry.subject.name ] }
        .first(limit)
  end

  private

  def classroom_total(classroom)
    classroom.users.where(role: :student).sum(:points)
  end

  def classroom_avg(classroom)
    students = classroom.users.where(role: :student)
    count = students.count
    count.zero? ? 0 : (students.sum(:points).to_f / count).round(1)
  end

  def complete_form_count(student)
    student.user_monsters.joins(:monster_species)
           .where(monster_species: { stage: MonsterSpecies::MAX_STAGE }).count
  end
end
