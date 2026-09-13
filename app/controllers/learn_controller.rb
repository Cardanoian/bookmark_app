# 단계 학습 위저드 5단계(P5.5, RAILS_PLAN §13.3). 2022 개정 성취기준 코드를 단계마다 주입한다.
# 진행은 학생 행(LearnWizardProgress)에 저장되어 이탈하거나 다른 기기로 옮겨도 이어지고, 다섯 단계를
# 마치면 답을 모아 미제출 독후감 초안을 만들어 그 편집 화면으로 보낸다(자동 저장이 곧바로 이어받는다).
#
# 2026-09-13 전에는 진행을 세션 쿠키에 쌓고 마칠 때 본문 전체를 새 글 주소에 실어 보냈다. 답을 합쳐
# 한글 약 750자면 쿠키(4KB)가 넘쳐 500 이 났고, 약 1,100자면 Puma 주소 한도(쿼리 10KB)에 걸렸다.
class LearnController < ApplicationController
  # 5단계 정의(순서 고정). codes = 학년군별 성취기준, prompt = 학생 안내 질문.
  #
  # 성취기준은 학생 학년군 것만 보여 준다(2026-09-13). 예전에는 모든 학년에 5~6학년 코드를 보여 줘,
  # 첨삭이 지키는 "상위 학년 성취기준을 요구하지 않는다"(ReadingDomain allowlist)와 어긋났다.
  # 코드는 교육부 고시 제2022-33호 [별책 5] 원문(app/views/monsters/성취기준.md)에서 단계 뜻에 맞는
  # 것을 골랐다 — 3단계 3~4학년군 [4국05-03](마음에 드는 작품 소개)은 원문 내용 체계에서 5~6학년
  # '인상적인 부분을 중심으로 의견 나누기'([6국05-04])의 바로 앞 단계(문학·비평)다.
  STEPS = [
    { codes: { g12: "[2국02-05]", g34: "[4국02-06]", g56: "[6국02-05]" }, title: "책 고르기",
      prompt: "어떤 책을 읽었나요? 책 제목과 그 책을 고른 까닭을 적어 보세요." },
    { codes: { g12: "[2국02-03]", g34: "[4국02-02]", g56: "[6국05-03]" }, title: "줄거리",
      prompt: "책의 줄거리를 사건 순서대로 간단히 정리해 보세요." },
    { codes: { g12: "[2국05-02]", g34: "[4국05-03]", g56: "[6국05-04]" }, title: "인상 깊은 장면",
      prompt: "가장 인상 깊었던 장면과 그 까닭을 적어 보세요." },
    { codes: { g12: "[2국03-02]", g34: "[4국03-03]", g56: "[6국03-03]" }, title: "내 생각·느낌",
      prompt: "그 장면에서 든 나의 생각과 느낌을 구체적으로 적어 보세요." },
    { codes: { g12: "[2국02-04]", g34: "[4국05-02]", g56: "[6국05-06]" }, title: "삶과 연결",
      prompt: "이 책이 나의 삶·경험과 어떻게 연결되는지 적어 보세요." }
  ].freeze

  STEP_COUNT = STEPS.length

  def index
    authorize :learn, :index?

    progress = LearnWizardProgress.find_or_initialize_by(user: Current.user)
    @step = progress.step.to_i.clamp(1, STEP_COUNT)
    @definition = STEPS[@step - 1]
    # 학년 미상(학급 없음)은 5~6학년이 아니라 최저 학년군으로 본다 — 질문형 작성과 같은 규칙.
    @standard_code = @definition[:codes].fetch(ReadingDomain.guided_band_for(Current.user.classroom&.grade))
    @answers = progress.answers
    @answer = @answers[@step.to_s].to_s
  end

  # 현재 단계 답을 저장하고 다음 단계로. 마지막 단계면 답을 모아 독후감 초안을 만든다.
  def advance
    authorize :learn, :advance?

    step = submitted_step
    return complete_wizard if step >= STEP_COUNT

    with_progress do |progress|
      progress.update!(step: step + 1, answers: progress.answers.merge(step.to_s => params[:answer].to_s))
    end
    redirect_to learn_index_path
  end

  private

  def submitted_step
    params[:step].to_i.clamp(1, STEP_COUNT)
  end

  # 진행 행은 트랜잭션 안에서 읽고 쓴다. SQLite 는 트랜잭션을 BEGIN IMMEDIATE 로 열어 쓰기 요청을 차례로
  # 세우므로, 두 탭이 동시에 답을 보내도 서로의 답(JSON 을 통째로 쓴다)을 지우지 않는다(마치기도 같은 방식이라
  # 초안을 두 편 만들지 않는다 — complete_wizard). 행은 첫 답을 낼 때 만든다(보기만 해서는 만들지 않는다).
  def with_progress
    LearnWizardProgress.transaction { yield LearnWizardProgress.find_or_create_by!(user: Current.user) }
  end

  # 다섯 답을 모아 **미제출 독후감 초안**('작성 중')을 만들고 그 편집 화면으로 보낸다. 제출이 아니다 —
  # submitted_at 이 없어 교사 큐·AI 첨삭 대상이 아니고, 아이가 편집 화면에서 다듬어 '제출하기'로 낸다.
  # 편집 화면은 이 초안의 자동 저장을 곧바로 켠다. 본문을 주소에 싣지 않으므로 길이 한도가 없다.
  #
  # 챌린지에 막 참여했으면 그 챌린지를 잇는다(link_participation — 예전에는 새 글 화면의 첫 저장이 했다).
  # 초안을 못 만드는 경우는 답을 남긴 채 위저드로 돌려보내고 까닭을 한국어로 알린다(모델 검증 문구는 영어다).
  # · 1단계 첫 줄(책 제목)이 비었다 — Report 의 책 참조 검증. 1단계로 보낸다.
  # · 학급이 없다 — Report 는 학급이 필수라 아이가 스스로 풀 수 없다. 선생님께 말하게 한다.
  def complete_wizard
    report = Current.user.reports.new(input_mode: :keyboard, classroom: Current.user.classroom)
    authorize report, :create? # 독후감은 학생만 쓴다

    outcome = LearnWizardProgress.transaction do
      # 진행 행이 없다 = 같은 위저드를 방금 다른 요청(연타·다른 탭)이 마쳐 초안을 만들고 지웠다. 여기서 빈 행을
      # 새로 만들면 "1단계 첫 줄이 비었어요"로 보여, 다 쓴 아이가 답이 사라진 줄 안다(B·C 리뷰).
      progress = LearnWizardProgress.find_by(user: Current.user)
      next :already_done unless progress

      answers = progress.answers.merge(STEP_COUNT.to_s => params[:answer].to_s)
      report.book_title = answers["1"].to_s.strip.lines.first.to_s.strip
      report.body = compose_body(answers)

      problem = if report.book_title.blank? then :no_title
      elsif report.classroom.nil? then :no_classroom
      elsif !report.valid? then :invalid
      end
      if problem
        progress.update!(step: problem == :no_title ? 1 : STEP_COUNT, answers: answers)
        next problem
      end

      link_participation(report)
      report.save!
      progress.destroy!
      :created
    end

    case outcome
    when :created
      redirect_to edit_report_path(report),
                  notice: "단계 학습을 마쳤어요! 모은 내용을 '작성 중' 독후감으로 저장했어요. 다듬어서 제출해 보세요."
    when :already_done
      redirect_to reports_path, notice: "단계 학습은 이미 마쳤어요. '작성 중' 독후감을 이어서 써 보세요."
    when :no_title
      redirect_to learn_index_path, alert: "1단계 첫 줄에 읽은 책 제목을 적어 주세요. 쓴 답은 그대로 있어요."
    when :no_classroom
      redirect_to learn_index_path, alert: "아직 학급이 정해지지 않아 독후감을 만들 수 없어요. 선생님께 말씀드려 주세요. 쓴 답은 그대로 있어요."
    else
      redirect_to learn_index_path, alert: "독후감을 만들지 못했어요. 쓴 답은 그대로 있으니 잠시 뒤 다시 해 보세요."
    end
  end

  def compose_body(answers)
    STEPS.each_with_index.map do |definition, index|
      "[#{definition[:title]}] #{answers[(index + 1).to_s]}"
    end.join("\n\n")
  end
end
