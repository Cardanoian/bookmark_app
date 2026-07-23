# NEIS 생기부 자동요약(P6.4). 학교 소속 학생 1명을 선택하면 그 학생의 독후감에서
# 독서활동상황 생기부 문장을 오프라인 템플릿으로 생성한다(API 키 불필요, 복사 사용).
# Ai::GeminiClient.available? 이면 향상 여지가 있으나 현재 기본은 오프라인 템플릿.
class SchoolAdmin::NeisController < SchoolAdmin::BaseController
  def index
    @school = current_school
    classroom_ids = @school ? @school.classrooms.select(:id) : []
    @students = User.where(classroom_id: classroom_ids, role: :student).order(:name)
    @student = @students.find_by(id: params[:student_id])

    return unless @student

    @reports = Report.where(user_id: @student.id, classroom_id: classroom_ids)
                     .includes(:book).order(:created_at).to_a
    @summary = build_summary(@student, @reports)
  end

  private

  # 독후감 데이터에서 생기부 독서활동 문장을 생성한다(3인칭 문어체 오프라인 템플릿).
  def build_summary(student, reports)
    return "#{student.name} 학생은 아직 작성한 독후감이 없어 요약할 독서활동이 없음." if reports.empty?

    titles = reports.filter_map { |report| report.book&.title.presence || report.book_title.presence }.uniq
    sentences = [ "#{student.name} 학생은 총 #{reports.size}편의 독후감을 작성함." ]
    sentences << "#{book_phrase(titles)}을 읽으며 꾸준히 독서 활동에 참여함." if titles.any?

    strength = strongest_axis(student, reports)
    if strength
      sentences << "특히 #{strength[:label]}(#{strength[:standard]}) 영역에서 우수한 성취를 보이며 " \
                   "책의 내용을 깊이 있게 이해하고 표현함."
    end

    sentences << "고쳐쓰기를 통해 글쓰기 능력이 향상되는 성장의 모습을 보임." if grew?(reports)

    sentences.join(" ")
  end

  def book_phrase(titles)
    shown = titles.first(3).map { |title| "「#{title}」" }
    phrase = shown.join(", ")
    titles.size > 3 ? "#{phrase} 등" : phrase
  end

  # 5축 평균 중 가장 높은 축(강점) → 학생의 현재 학년군에 맞는 라벨 + 성취기준.
  # NEIS 요약은 학생 한 명을 대상으로 하므로 전교 집계용 g56 기본값을 쓰지 않는다.
  def strongest_axis(student, reports)
    averages = axis_averages(reports)
    return nil if averages.values.all?(&:zero?)

    axis, _score = averages.max_by { |_, value| value }
    band = ReadingDomain.band_for(student.classroom&.grade)
    { axis: axis, label: ReadingDomain::AXIS_LABELS[axis], standard: ReadingDomain.achievement_standards(band)[axis] }
  end

  def grew?(reports)
    reports.any? { |report| report.improvement.to_f.positive? }
  end
end
