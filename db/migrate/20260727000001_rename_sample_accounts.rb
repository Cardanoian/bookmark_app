class RenameSampleAccounts < ActiveRecord::Migration[8.1]
  # 포항원동초 샘플 계정의 이름이 역할 플레이스홀더(김담임·박교무·최사서·이학생·홍길동)이고 이메일도
  # @example.com 이라 심사·시연에서 "실제로 운영 중인 학교"로 보이지 않는다. db/seeds.rb 의 seed_user 는 교직원을 **이메일로**,
  # 이메일 없는 학생을 **이름으로** 식별하므로 accounts.yml 만 고치면 기존 행이 개명되는 대신 새 사용자가
  # 생겨 담임이 둘이 되고 이학생의 독후감 13건이 학급에서 고아가 된다. 그래서 시드보다 먼저 도는 이
  # 마이그레이션이 기존 행을 직접 개명한다(데이터 전용 선례: 20260719190354 book_title squish,
  # 20260719210000 cover_url https 승격).
  #
  # 멱등: **옛 식별자로만** 찾으므로 이미 개명된 DB·새로 만든 빈 DB에서는 대상 0건으로 no-op 한다.
  # 새 DB 는 이 마이그레이션 뒤에 도는 시드가 accounts.yml 의 새 이름으로 처음부터 만든다.
  #
  # 비밀번호: seed_user 는 기존 행의 비밀번호를 절대 바꾸지 않는 계약이라(db/CLAUDE.md), accounts.yml
  # 갱신만으로는 이미 존재하는 담임의 비밀번호가 옛 값으로 남는다 → 여기서 함께 갱신한다.
  SCHOOL_NEIS_CODE = "8761159"
  SAMPLE_GRADE = 3
  SAMPLE_CLASS_NO = 1

  # 역할별 샘플 교직원. 옛 이메일이 안정 식별자라 그 값으로 찾아 이름·이메일·비밀번호를 함께 바꾼다.
  STAFF_RENAMES = [
    { role: :teacher,
      old: { name: "김담임", email: "teacher@example.com", password: "teacher1234" },
      new: { name: "김지은", email: "jieun@gbeai.net", password: "jieun11!" } },
    { role: :school_admin,
      old: { name: "박교무", email: "schooladmin@example.com", password: "schooladmin1234" },
      new: { name: "박은수", email: "eunsu@gbeai.net", password: "eunsu11!" } },
    { role: :librarian,
      old: { name: "최사서", email: "librarian@example.com", password: "librarian1234" },
      new: { name: "최지혜", email: "jihye@gbeai.net", password: "jihye11!" } }
  ].freeze

  STUDENT_RENAMES = { "이학생" => "이도현", "홍길동" => "홍수아" }.freeze

  def up
    apply(:old, :new, STUDENT_RENAMES)
  end

  def down
    apply(:new, :old, STUDENT_RENAMES.invert)
  end

  private

  def apply(from_key, to_key, student_renames)
    User.reset_column_information
    school = School.find_by(neis_code: SCHOOL_NEIS_CODE)
    unless school
      say "샘플 학교(neis=#{SCHOOL_NEIS_CODE}) 없음 — 개명 대상 없음."
      return
    end

    STAFF_RENAMES.each do |entry|
      rename_staff(school, entry.fetch(:role), entry.fetch(from_key), entry.fetch(to_key))
    end
    student_renames.each { |from, to| rename_student(school, from, to) }
  end

  def rename_staff(school, role, from, to)
    staff = User.find_by(school_id: school.id, email: from[:email], role: role)
    unless staff
      say "샘플 #{role}(#{from[:email]}) 없음 — 건너뜀."
      return
    end

    if User.where(email: to[:email]).where.not(id: staff.id).exists?
      say "이미 #{to[:email]} 계정이 있어 #{role} 개명을 건너뜀."
      return
    end

    staff.name = to[:name]
    staff.email = to[:email]
    staff.password = to[:password]
    staff.save!
    say "샘플 #{role} 개명: #{from[:name]} → #{to[:name]} (#{to[:email]}, 비밀번호 갱신)"
  end

  # 샘플 학급은 학년도별로 여러 행이 있을 수 있으므로 academic_year 는 조건에서 뺀다(3-1 전체).
  def rename_student(school, from, to)
    classroom_ids = Classroom.where(
      school_id: school.id, grade: SAMPLE_GRADE, class_no: SAMPLE_CLASS_NO
    ).pluck(:id)
    if classroom_ids.empty?
      say "샘플 학급(#{SAMPLE_GRADE}-#{SAMPLE_CLASS_NO}) 없음 — 학생 개명 건너뜀."
      return
    end

    student = User.find_by(school_id: school.id, classroom_id: classroom_ids, name: from, role: :student)
    unless student
      say "샘플 학생(#{from}) 없음 — 건너뜀."
      return
    end

    if User.where(school_id: school.id, classroom_id: student.classroom_id, name: to).exists?
      say "이미 #{to} 학생이 있어 개명을 건너뜀."
      return
    end

    # 콜백·타임스탬프를 우회해 실사용 독후감·포인트를 가진 행을 이름만 바꾼다.
    student.update_columns(name: to)
    say "샘플 학생 개명: #{from} → #{to}"
  end
end
