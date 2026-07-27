# 체험 계정(샘플 학급 포항원동초 3-1) 조회의 단일 진실.
#
# `db/seeds/accounts.yml` 의 sample_accounts 와 **같은 신원 규약**을 쓴다 — 학생은 (학교 neis_code +
# 학년/반 + 이름), 교직원은 이메일. 시드·개명 마이그레이션(20260727000001)이 쓰는 키와 동일하므로
# 재시드나 개명이 있어도 조회가 어긋나지 않는다.
#
# 로그인 화면의 "바로 체험해 보기" 버튼(`sessions#new`)과 원클릭 로그인(`sessions#demo_create`)이
# 함께 쓴다. 시드가 돌지 않은 DB(운영 기본)에서는 nil 을 돌려 화면이 버튼을 통째로 숨기므로,
# 계정이 없는 환경에 죽은 버튼이 남지 않는다.
module DemoAccounts
  SCHOOL_NEIS_CODE = "8761159" # 포항원동초등학교
  GRADE = 3
  CLASS_NO = 1
  STUDENT_NAME = "이도현"
  TEACHER_EMAIL = "jieun@gbeai.net"

  module_function

  # role 화이트리스트. 알 수 없는 값은 nil 이라 호출부(컨트롤러)가 거부한다.
  def find(role)
    case role
    when "student" then student
    when "teacher" then teacher
    end
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

  def teacher
    User.where.not(role: :student).find_by(email: TEACHER_EMAIL)
  end

  # 같은 학교의 같은 학년·반이 학년도별로 공존하므로(마이그레이션 #38) 최신 학년도를 고른다.
  def demo_classroom
    school = School.find_by(neis_code: SCHOOL_NEIS_CODE)
    return nil if school.nil?

    school.classrooms.where(grade: GRADE, class_no: CLASS_NO).order(academic_year: :desc).first
  end
end
