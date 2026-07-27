class SessionsController < ApplicationController
  # 로그인 브루트포스 방어(0.5, #7 · Phase 6 보안검토 후속). **fail2ban + 정답-우선** 방식:
  #   - **먼저 인증**한다. 정답이면 항상 로그인시키고(락아웃되지 않는다) IP·계정 실패 카운터를
  #     리셋한다 → 저엔트로피 파라미터(학교·학급·이름)로 피해자 계정을 잠그는 DoS 가 무력화된다
  #     (피해자는 언제나 정답으로 들어와 스스로 해제). 정답은 실패로 세지 않으므로, 전산실 단일
  #     공인 IP(NAT) 뒤에서 학급 20~30명이 동시에 정답 로그인해도 IP 한도에 걸리지 않는다.
  #   - **오답만** 카운트하고, 오답이 한도를 넘으면(추가 추측) 락아웃한다. 즉 락아웃은 "추측"만
  #     막고 정답은 막지 않는다. 두 축: ① IP 실패(3분 10회) ② 계정 실패(10분 8회).
  #
  # 계정 키는 조회된 **user.id** 로 정규화한다(존재 시). 원문 문자열 id 는 "5"/"05"/" 5" 가 서로
  # 다른 버킷을 만들어 계정 축을 우회할 수 있으므로 쓰지 않는다. 미존재(오타/추측) 계정만 정규화 튜플.
  #
  # fail2ban 코어(IP_THROTTLE/ACCOUNT_THROTTLE·락아웃·실패기록·리셋·rate_limit_store 시임)는
  # LoginThrottling concern 으로 추출해 AccountLinksController(계정 연동 인증)와 공유한다. 이 컨트롤러는
  # **로그인 IP 축(login:ip:...) + 계정 축(login:account:...)** 키를 만들어 넘긴다(축 키만 컨트롤러 소유).
  #
  # 로그인 표면은 둘로 나뉜다(신원 방식만 다르고 위 방어 로직은 공유):
  #   - 학생(student_create): (학교·학급·이름) 튜플 + 비밀번호. 조회는 학생 역할로 한정한다.
  #   - 교직원(staff_create): 이메일 + 비밀번호. 조회는 학생 이외 역할로 한정한다.
  include LoginThrottling

  skip_before_action :require_login,
    only: [ :new, :student_new, :student_create, :staff_new, :staff_create, :demo_create ]
  skip_before_action :require_student_ranking_profile
  # 로그인/로그아웃·안내 진입점 — 인가할 리소스가 없다(공개·인증 흐름).
  skip_after_action :verify_authorized

  # 처음 접속 시 안내 인덱스 — 학생 로그인 / 교직원 로그인 선택 화면(폼 없음).
  # 체험 계정이 DB 에 있을 때만 "바로 체험해 보기" 섹션을 렌더하도록 두 계정을 조회한다.
  def new
    load_demo_accounts
  end

  # 학생 로그인 폼(시도·시군구·학교·학급·이름·비밀번호).
  def student_new
    load_form_collections
  end

  def student_create
    attempt_login(
      user: find_student,
      account_key: student_account_key,
      failure_message: "학교·학급·이름·비밀번호를 다시 확인해 주세요.",
      form: :student_new
    )
  end

  # 교직원(교사·교무관리자·사서·총괄관리자) 로그인 폼(이메일·비밀번호).
  def staff_new
  end

  def staff_create
    attempt_login(
      user: find_staff,
      account_key: staff_account_key,
      failure_message: "이메일 또는 비밀번호를 다시 확인해 주세요.",
      form: :staff_new
    )
  end

  # 체험 계정 원클릭 로그인(시연·심사·개발 진입 단축). 학생 로그인은 시도→시군구→학교→학년도→학급
  # →이름→비밀번호 7단계라 앱을 한 번 열어 보기가 무겁다. 비밀번호를 클라이언트로 내려보내지 않고
  # **role 만 받아 서버가 계정을 확정**하므로(DemoAccounts) 페이지 소스에 자격증명이 남지 않는다.
  # 자격증명을 받지 않으니 추측할 것도 없어 로그인 스로틀(LoginThrottling) 대상이 아니고,
  # 정지 계정 게이트만 기존 handle_authenticated 로 공유한다.
  def demo_create
    user = DemoAccounts.find(params[:role])
    return redirect_to new_session_path, alert: "체험 계정을 찾을 수 없어요." if user.nil?

    handle_authenticated(user, :new)
  end

  def destroy
    reset_session
    redirect_to new_session_path
  end

  private

  # 학생·교직원 공용 인증 흐름. 신원 조회(user)와 스로틀 계정 키(account_key)만 표면별로 다르다.
  def attempt_login(user:, account_key:, failure_message:, form:)
    keys = throttle_keys(account_key)
    if user&.authenticate(params[:password])
      reset_login_failures(**keys) # 정답 = 브루트포스 아님 → IP·계정 실패 카운터 해제(피해자 DoS·NAT 방지)
      handle_authenticated(user, form)
    elsif locked_out?(**keys)
      # 오답인데 이미 실패 한도 초과 → 추가 추측 차단(정답은 위에서 이미 통과했으므로 여기 안 온다).
      rerender_form(form, "로그인 시도가 너무 많아요. 잠시 후 다시 시도해 주세요.", :too_many_requests)
    else
      register_login_failure(**keys) # 오답 → IP·계정 실패 카운트 증가
      rerender_form(form, failure_message, :unprocessable_entity)
    end
  end

  # 로그인 스로틀 두 축 키. IP 축은 login:ip:*(연동은 linkauth:ip:* 로 분리), 계정 축은
  # login:account:*(연동과 공유 네임스페이스 — 한 계정 자격증명 브루트포스 표면을 합산).
  def throttle_keys(account_key)
    { ip_key: "login:ip:#{request.remote_ip}", account_key: "login:account:#{account_key}" }
  end

  # 정답 인증 후 계정 상태 게이트(정지 → 로그인 차단하되 실패로 세지 않음).
  def handle_authenticated(user, form)
    if user.suspended?
      rerender_form(form, "정지된 계정입니다. 관리자에게 문의해 주세요.", :forbidden)
    else
      reset_session
      session[:user_id] = user.id
      redirect_to root_path
    end
  end

  # 실패·차단 시 해당 로그인 폼을 flash 와 함께 재렌더. 학생 폼만 학교 피커 컬렉션이 필요하고,
  # 안내 인덱스(demo_create 의 정지 계정 경로)는 체험 계정 조회가 필요하다.
  def rerender_form(form, message, status)
    load_form_collections if form == :student_new
    load_demo_accounts if form == :new
    flash.now[:alert] = message
    render form, status: status
  end

  # 학생 스로틀 계정 키. 존재하는 계정은 안정적인 user.id 로 키잉(id 문자열 변형 우회 차단).
  # 미존재(오타/추측)만 정규화 튜플(id 를 정수화해 "5"/"05" 버킷 분열 방지).
  def student_account_key
    user = find_student
    return "user:#{user.id}" if user

    [ params[:school_id].to_i, params[:classroom_id].to_i, params[:name].to_s.strip.downcase ].join(":")
  end

  # 교직원 스로틀 계정 키. 존재 계정은 user.id, 미존재(오타/추측)는 정규화 이메일 문자열.
  def staff_account_key
    user = find_staff
    return "user:#{user.id}" if user

    "email:#{normalized_email}"
  end

  # 학생 튜플 신원(학교·학급·이름) 조회. 스로틀 키와 인증에서 공유하도록 메모이즈(중복 쿼리 방지).
  # 학생 역할로 한정해 교직원이 학생 폼으로 로그인하지 못하게 한다(신원 방식 격리).
  def find_student
    return @find_student if defined?(@find_student)

    @find_student = User.student.find_by(
      school_id: params[:school_id].presence,
      classroom_id: params[:classroom_id].presence,
      name: params[:name]
    )
  end

  # 교직원 이메일 신원 조회. 학생 이외 역할로 한정하고, 이메일이 비면 조회하지 않는다(nil).
  def find_staff
    return @find_staff if defined?(@find_staff)

    email = normalized_email
    return @find_staff = nil if email.blank?

    @find_staff = User.where.not(role: :student).find_by(email: email)
  end

  # 로그인 이메일 정규화(모델 저장 규칙과 동일 — 앞뒤 공백 제거 + 소문자).
  def normalized_email
    params[:email].to_s.strip.downcase
  end

  # 학생 로그인 학교 피커는 하이브리드라 전량 로드하지 않고 시도(교육청) 목록만 서버 렌더한다.
  # 학급은 학교 선택 시 /schools/:id/classrooms 로 스코프 조회한다(전국 전량 로드 제거, §2.2).
  def load_form_collections
    @regions = School.form_regions
    @current_academic_year = Classroom.current_academic_year
  end

  # 안내 인덱스의 "바로 체험해 보기" 섹션 노출 판단용. 시드가 돌지 않은 DB 에서는 둘 다 nil 이라
  # 섹션이 통째로 숨겨진다(죽은 버튼 방지 — 환경 분기 대신 계정 존재 여부로 판단).
  def load_demo_accounts
    @demo_student = DemoAccounts.student
    @demo_teacher = DemoAccounts.teacher
  end
end
