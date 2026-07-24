# 기존 데이터 백필(Phase 1 §1.4). 신규 컬럼 추가만으로는 content_axis/band 가 NULL 이라,
# 기존 교사 퀴즈를 origin=teacher / content_axis=mcq / band=학급 학년 유도(미상 g56) /
# content_version=1 로, 문항을 question_type=mcq_single / source=manual 로 채운다.
#
# up/down 왕복 무손실(§1.4): down 은 백필로 채운 유도값(content_axis·band)만 NULL 로 되돌린다.
# origin/content_version/question_type/source 는 컬럼 기본값(teacher/1/mcq_single/manual)과
# 동일하므로 되돌릴 필요가 없다. change 가 아니라 up/down 으로 두어 되돌림을 명시한다.
class BackfillQuizContentAxis < ActiveRecord::Migration[8.1]
  # ReadingDomain.band_for 와 동일한 학년→학년군 매핑의 정수 enum 값(Quiz.bands 미러).
  BAND_INT = { g12: 0, g34: 1, g56: 2 }.freeze
  CONTENT_AXIS_MCQ = 0        # Quiz.defined_enums["content_axis"]["mcq"] (content_axis 는 불변복수라 Quiz.content_axes 접근자 없음)
  ORIGIN_TEACHER = 0          # Quiz.origins[:teacher]
  QUESTION_TYPE_MCQ_SINGLE = 0 # QuizQuestion.question_types[:mcq_single]
  SOURCE_MANUAL = 0           # QuizQuestion.sources[:manual]

  def up
    say_with_time "backfill quizzes origin/content_axis/band + quiz_questions type/source" do
      execute(<<~SQL.squish)
        UPDATE quizzes
        SET origin = #{ORIGIN_TEACHER},
            content_axis = #{CONTENT_AXIS_MCQ},
            content_version = 1
        WHERE content_axis IS NULL
      SQL

      # band 는 학급 학년으로 유도(ReadingDomain.band_for). 학급 미상/미배정은 g56.
      select_rows("SELECT id, classroom_id FROM quizzes").each do |quiz_id, classroom_id|
        grade = classroom_id && select_value("SELECT grade FROM classrooms WHERE id = #{classroom_id.to_i}")
        band = BAND_INT.fetch(ReadingDomain.band_for(grade))
        execute "UPDATE quizzes SET band = #{band} WHERE id = #{quiz_id.to_i}"
      end

      execute "UPDATE quiz_questions SET question_type = #{QUESTION_TYPE_MCQ_SINGLE}, source = #{SOURCE_MANUAL}"
    end
  end

  def down
    say_with_time "revert content_axis/band backfill" do
      # 백필로 유도한 값만 되돌린다(NULL). 나머지는 컬럼 기본값과 동일해 손실 없음.
      execute "UPDATE quizzes SET content_axis = NULL, band = NULL"
      execute "UPDATE quiz_questions SET question_type = #{QUESTION_TYPE_MCQ_SINGLE}, source = #{SOURCE_MANUAL}"
    end
  end
end
