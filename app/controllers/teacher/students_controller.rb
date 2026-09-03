# 교사 학생 관리(P6.2). 담임 학급 학생 추가·삭제·비밀번호 초기화·수동 포인트 지급.
class Teacher::StudentsController < Teacher::BaseController
  # 이메일 인증 게이트는 **남의 계정을 만들고 조작하는 두 액션에만** 건다(학생 계정 생성·비번
  # 초기화). 목록·삭제·포인트·동의 기록은 이미 존재하는 학생을 다루므로 대상이 아니고, 검토·통계
  # 같은 읽기 경로도 계속 열려 있어 "잠기는 실패"가 되지 않는다.
  # 게이트 발동 조건은 `User#email_verification_gate_active?` 참조(무키 환경·가입 24시간 유예 내에는
  # 발동하지 않는다).
  before_action :require_verified_email!, only: [ :create, :reset_password ]
  before_action :set_student, only: [ :destroy, :reset_password, :give_points, :set_ai_consent ]

  # 정렬 화이트리스트. **화면에 보이는 값만** 정렬축으로 둔다 — 목록이 렌더하는 것은 이름·학급·
  # 포인트·경험치·레벨뿐이라, 예컨대 가입일로 정렬하면 교사가 결과를 눈으로 검증할 수 없다.
  SORTS = %w[name points experience].freeze
  DIRECTIONS = %w[asc desc].freeze
  DEFAULT_DIRECTIONS = { "name" => "asc" }.freeze

  def index
    @classrooms = teacher_classrooms.order(:academic_year, :grade, :class_no).to_a
    @query = params[:q].to_s.squish
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "name"
    @dir = DIRECTIONS.include?(params[:dir]) ? params[:dir] : DEFAULT_DIRECTIONS.fetch(@sort, "desc")

    # 이 화면은 통계 화면과 달리 **담임 학급 전체**를 한 목록에 합친다(학급 선택이 없다).
    # 같은 검색어라도 두 화면의 결과가 다를 수 있어 뷰가 범위를 문구로 밝힌다.
    scope = User.where(classroom_id: @classrooms.map(&:id), role: :student)
    scope = scope.where("name LIKE ? ESCAPE '\\'", "%#{sanitize_like(@query)}%") if @query.present?
    @students = scope.order(@sort => @dir.to_sym, :name => :asc)
  end

  def create
    classroom = owned_classroom!(target_classroom)
    password = student_params[:password]
    if password.blank?
      return redirect_to teacher_students_path, alert: "비밀번호를 6자 이상 입력해 주세요."
    end

    # 개인정보 필수동의(§1) 수령 확인이 없으면 계정을 만들지 않는다(P1-1). 동의 필드는 permit 에
    # 넣지 않고 서버가 직접 소비해 위조·mass-assignment 를 막는다(성적 조정 standard_code 선례).
    unless params.dig(:student, :privacy_consent) == "1"
      return redirect_to teacher_students_path, alert: "보호자 개인정보 수집·이용 동의서 수령을 확인해 주세요."
    end
    ai_ok = params.dig(:student, :ai_consent) == "1"

    @student = User.new(
      name: student_params[:name],
      classroom: classroom,
      school_id: classroom.school_id,
      role: :student,
      password: password,
      privacy_consent_at: Time.current,
      ai_consent: ai_ok,
      ai_consent_at: (Time.current if ai_ok),
      ai_consent_recorded_by_id: (Current.user.id if ai_ok)
    )

    if @student.save
      audit!("teacher.student_create", target: @student, metadata: { ai_consent: ai_ok })
      redirect_to teacher_students_path, notice: "#{@student.name} 학생을 추가했어요."
    else
      redirect_to teacher_students_path, alert: @student.errors.full_messages.to_sentence
    end
  end

  def destroy
    name = @student.name
    User.transaction do
      @student.destroy!
      audit!("teacher.student_delete", target: @student)
    end
    redirect_to teacher_students_path, notice: "#{name} 학생을 삭제했어요."
  end

  def reset_password
    password = params.permit(student: [ :password ]).dig(:student, :password)
    if password.blank?
      return redirect_to teacher_students_path, alert: "비밀번호를 6자 이상 입력해 주세요."
    end

    updated = User.transaction do
      next false unless @student.update(password: password)

      audit!("teacher.password_reset", target: @student)
      true
    end

    if updated
      redirect_to teacher_students_path, notice: "#{@student.name} 학생의 비밀번호를 초기화했어요."
    else
      redirect_to teacher_students_path, alert: "비밀번호를 6자 이상 입력해 주세요."
    end
  end

  def give_points
    raw_amount = params[:points].presence || "10"
    unless raw_amount.to_s.match?(/\A[1-9]\d*\z/)
      return redirect_to teacher_students_path, alert: "선물할 포인트는 1 이상의 정수여야 해요."
    end

    amount = raw_amount.to_i
    points_before = @student.points
    User.transaction do
      @student.award_points(amount, reason: "교사 수동 지급")
      audit!(
        "teacher.points_grant",
        target: @student,
        metadata: { amount: amount, points_before: points_before, points_after: @student.points }
      )
    end
    redirect_to teacher_students_path,
                notice: "#{@student.name} 학생에게 #{amount}포인트와 #{amount}경험치를 지급했어요."
  end

  # AI 활용 동의 기록/철회(P1-1, 멱등 set). 명시적 목표값(consent 파라미터)으로 flip 이 아닌 set 을
  # 해 이중클릭·동시요청에 안전하다. 동의를 켜면 §1 개인정보 동의도 함께 스탬프(교사가 §1+§2 결합
  # 동의서를 받은 것이므로) — 단 기존 값은 덮어쓰지 않는다(정직). owned_student! 로 학급 경계 강제.
  def set_ai_consent
    granting = params[:consent] == "1"
    @student.update!(
      ai_consent: granting,
      ai_consent_at: Time.current,
      ai_consent_recorded_by_id: Current.user.id,
      privacy_consent_at: @student.privacy_consent_at || (granting ? Time.current : nil)
    )
    audit!("teacher.ai_consent_set", target: @student, metadata: { ai_consent: granting })
    state = granting ? "동의로 기록했어요" : "철회로 기록했어요"
    redirect_to teacher_students_path, notice: "#{@student.name} 학생의 AI 활용을 #{state}."
  end

  private

  # LIKE 특수문자(% _)를 이스케이프한다 — 안 하면 "%" 한 글자로 전원이 매칭된다.
  def sanitize_like(value)
    value.gsub(/[\\%_]/) { |char| "\\#{char}" }
  end

  def set_student
    @student = owned_student!(User.find(params[:id]))
  end

  # 지정 학급(없으면 담임 첫 학급).
  def target_classroom
    Classroom.find_by(id: student_params[:classroom_id]) || teacher_classrooms.first
  end

  def student_params
    params.require(:student).permit(:name, :classroom_id, :password)
  end
end
