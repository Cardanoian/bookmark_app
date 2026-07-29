# 체험 계정(샘플 학교 = 가상 학교 「테스트초등학교」, 3-1 학급) 조회의 단일 진실.
#
# `db/seeds/accounts.yml` 의 sample_accounts 와 **같은 신원 규약**을 쓴다 — 학생은 (학교 neis_code +
# 학년/반 + 이름), 교직원은 이메일. 시드·개명 마이그레이션(20260727000001)이 쓰는 키와 동일하므로
# 재시드나 개명이 있어도 조회가 어긋나지 않는다.
#
# 역할은 학생·담임교사·교무관리자·사서 4종이다(총괄관리자는 전역 콘솔이라 체험 대상이 아니다).
#
# 로그인 화면의 "바로 체험해 보기" 버튼(`sessions#new`)과 원클릭 로그인(`sessions#demo_create`)이
# 함께 쓴다. 시드가 돌지 않은 DB(운영 기본)에서는 nil/빈 해시를 돌려 화면이 버튼을 통째로 숨기므로,
# 계정이 없는 환경에 죽은 버튼이 남지 않는다.
module DemoAccounts
  # 전국 NEIS 스냅샷에 없는 **가상 학교**의 자리표 코드. 데모 자료를 실학교에 얹으면 그 학교의
  # 실제 구성원과 섞이고 제출물·화면에 실학교명이 새어 나오므로, 체험 자료는 전부 이 학교에 모은다.
  # 학교 행 자체는 `db/seeds/accounts.yml` 의 sample_accounts.school 이 단일 진실이다.
  SCHOOL_NEIS_CODE = "9999999" # 테스트초등학교(세종특별자치시교육청, data_source=manual)
  GRADE = 3
  CLASS_NO = 1
  STUDENT_NAME = "이도현"
  TEACHER_EMAIL = "jieun@gbeai.net"
  SCHOOL_ADMIN_EMAIL = "eunsu@gbeai.net"
  LIBRARIAN_EMAIL = "jihye@gbeai.net"

  # 교직원 체험 계정의 role → 이메일. 이 해시가 곧 role 화이트리스트이자 화면 노출 순서다.
  STAFF_EMAILS = {
    "teacher" => TEACHER_EMAIL,
    "school_admin" => SCHOOL_ADMIN_EMAIL,
    "librarian" => LIBRARIAN_EMAIL
  }.freeze

  ROLES = [ "student", *STAFF_EMAILS.keys ].freeze

  module_function

  # role 화이트리스트. 알 수 없는 값은 nil 이라 호출부(컨트롤러)가 거부한다.
  def find(role)
    return student if role == "student"

    email = STAFF_EMAILS[role]
    staff(email) if email
  end

  # 실제로 존재하는 체험 계정만 ROLES 순서대로 담은 { role => User }. 시드가 돌지 않은 DB 에서는
  # 빈 해시라 로그인 화면이 "바로 체험해 보기" 섹션을 통째로 숨긴다(환경 분기 없음).
  def available
    ROLES.index_with { |role| find(role) }.compact
  end

  def student
    classroom = demo_classroom
    return nil if classroom.nil?

    User.student.find_by(
      school_id: classroom.school_id,
      classroom_id: classroom.id,
      name: STUDENT_NAME
    )
  end

  # 교직원은 이메일이 안정 식별자다. 학생 역할은 제외해 학생 폼 신원 규약과 섞이지 않게 한다.
  def staff(email)
    User.where.not(role: :student).find_by(email: email)
  end

  # 같은 학교의 같은 학년·반이 학년도별로 공존하므로(마이그레이션 #38) 최신 학년도를 고른다.
  def demo_classroom
    school = School.find_by(neis_code: SCHOOL_NEIS_CODE)
    return nil if school.nil?

    school.classrooms.where(grade: GRADE, class_no: CLASS_NO).order(academic_year: :desc).first
  end
end
