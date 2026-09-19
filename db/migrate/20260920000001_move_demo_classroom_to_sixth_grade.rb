class MoveDemoClassroomToSixthGrade < ActiveRecord::Migration[8.1]
  # 공개 체험 학급(테스트초등학교 김지은 담임 반)을 3-1 에서 6-1 로 옮긴다(2026-09-20 사용자 요청 — 보고서의
  # 적용 학년이 6학년이다). 6-1 자리에는 이미 템플릿 학급(이수민 담임)이 있어 (학교·학년도·학년·반) UNIQUE 에
  # 걸리므로, 그 학급을 비어 있던 6-4 로 먼저 옮긴다. 시드 정본도 같이 바뀌었다
  # (accounts.yml·demo/sample_6_1.yml[옛 sample_3_1.yml]·demo/sample_6_4.yml[옛 sample_6_1.yml]).
  #
  # 이 마이그레이션이 없으면 새 코드의 DemoAccounts(6-1)가 체험 학생을 찾지 못해 로그인 화면의 학생 체험
  # 버튼이 사라지고, 재시드는 6-1 이 이미 있어 체험 학급을 만들지 못한다.
  #
  # 대상은 담임 이메일로 한정한다 — 같은 학년·반에 실제 교사가 연 학급이 있으면 건드리지 않는다. 옮길 자리가
  # 이미 차 있으면 **멈춘다**(건너뛰고 적용 완료로 기록하면 새 코드의 DemoAccounts 가 엉뚱한 학급을 가리킨다.
  # 여기서 실패하면 새 컨테이너가 뜨지 않아 Kamal 이 옛 판본을 그대로 둔다). 옛 자리로만 찾으므로 이미 옮긴
  # DB·학급이 아직 없는 새 DB 에서는 no-op 이다(새 DB 는 이 뒤에 도는 시드가 처음부터 6-1·6-4 로 만든다).
  #
  # 학년에서 나와 행에 저장된 값도 함께 고친다. 학년이 바뀐 게 아니라 학급 정보를 바로잡는 것이기 때문이다.
  # · season_scores.grade — 적립 당시 학년 스냅샷(랭킹 그룹핑에는 안 씀). 같은 학년도 행.
  # · 학생 문제 기여(quiz_contributions.band) — 담임 검토 화면이 이 밴드를 미리 고르고, 승인 퀴즈가 이 밴드로
  #   전국 풀에 들어간다. 승인된 기여는 새 밴드로도 한 번 더 물질화한다(ContributionPublisher). 게임 공개 여부는
  #   학생 학년의 밴드로 판정하므로, 옛 밴드 퀴즈만 있으면 이 기여로 열리던 게임이 6학년이 된 학급에서 닫힌다.
  #   옛 밴드 퀴즈는 이미 전국 풀에 들어간 것이라 그대로 둔다. 같은 문항이 새 밴드에 있으면 다시 만들지 않는다.
  # · 담임 퀴즈(quizzes.band, origin=teacher) — 플레이는 학급 경계로만 막아 동작 영향은 없지만 시드와 맞춘다.
  SCHOOL_NEIS_CODE = "9999999"
  DEMO_TEACHER_EMAIL = "jieun@gbeai.net"
  DISPLACED_TEACHER_EMAIL = "teacher.sample61@chaekgalpi.demo"

  def up
    relocate(DISPLACED_TEACHER_EMAIL, from: [ 6, 1 ], to: [ 6, 4 ])
    relocate(DEMO_TEACHER_EMAIL, from: [ 3, 1 ], to: [ 6, 1 ]).each do |classroom|
      rebase_bands(classroom, from: "g34", to: "g56")
    end
  end

  def down
    relocate(DEMO_TEACHER_EMAIL, from: [ 6, 1 ], to: [ 3, 1 ]).each do |classroom|
      rebase_bands(classroom, from: "g56", to: "g34")
    end
    relocate(DISPLACED_TEACHER_EMAIL, from: [ 6, 4 ], to: [ 6, 1 ])
  end

  private

  # 옮긴 학급 목록을 돌려준다.
  def relocate(teacher_email, from:, to:)
    school = School.find_by(neis_code: SCHOOL_NEIS_CODE)
    unless school
      say "체험 학교(neis=#{SCHOOL_NEIS_CODE}) 없음 — 건너뜀."
      return []
    end

    classrooms = school.classrooms.joins(:teacher)
                       .where(users: { email: teacher_email }, grade: from[0], class_no: from[1]).to_a
    say "#{teacher_email} 의 #{from.join('-')} 학급 없음 — 건너뜀." if classrooms.empty?

    classrooms.each do |classroom|
      label = "#{classroom.academic_year}학년도 #{from.join('-')}"
      if school.classrooms.exists?(academic_year: classroom.academic_year, grade: to[0], class_no: to[1])
        raise "#{label} → #{to.join('-')}: 옮길 자리에 이미 학급이 있습니다(#{teacher_email})"
      end

      classroom.update_columns(grade: to[0], class_no: to[1], updated_at: Time.current)
      scores = SeasonScore.where(classroom_id: classroom.id, academic_year: classroom.academic_year)
                          .update_all(grade: to[0], updated_at: Time.current)
      say "#{label} → #{to.join('-')} (classroom ##{classroom.id}, season_scores #{scores}행)"
    end
  end

  def rebase_bands(classroom, from:, to:)
    quizzes = Quiz.where(classroom_id: classroom.id, origin: :teacher, band: from)
                  .update_all(band: Quiz.bands.fetch(to), updated_at: Time.current)

    published = 0
    contributions = QuizContribution.where(classroom_id: classroom.id, band: from).to_a
    contributions.each do |contribution|
      contribution.update_columns(band: QuizContribution.bands.fetch(to), updated_at: Time.current)
      next unless contribution.approved?
      next if published_in_band?(contribution.reload)

      Games::ContributionPublisher.publish!(contribution)
      published += 1
    end
    say "#{from} → #{to}: 담임 퀴즈 #{quizzes}개, 학생 기여 #{contributions.size}건(새 밴드 공개 #{published}건)"
  end

  # 이 기여 문항이 기여의 현재 밴드 전국 풀에 이미 있는지(mcq=질문 / hint_reveal=정답으로 비교).
  def published_in_band?(contribution)
    quizzes = Quiz.where(origin: :system, book_id: contribution.book_id,
                         band: contribution.band, content_axis: contribution.content_axis)
    data = contribution.payload_hash
    QuizQuestion.where(quiz: quizzes, source: :contributed).any? do |question|
      if contribution.content_axis == "mcq"
        question.prompt.to_s == data[:prompt].to_s
      else
        question.answer.to_s == data[:answer].to_s
      end
    end
  end
end
