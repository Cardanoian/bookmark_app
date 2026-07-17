# 교사 퀴즈 관리(P6.2). 담임 학급 독서 퀴즈 CRUD. 도서 선택 시 Ai::QuizDraftService
# 로 초안 문항을 생성(오프라인 폴백) → 교사 검수/수정 → published 로 학생 노출.
class Teacher::QuizzesController < Teacher::BaseController
  before_action :set_quiz, only: [ :show, :edit, :update, :destroy ]
  before_action :set_form_collections, only: [ :new, :create, :edit, :update ]

  def index
    @quizzes = Quiz.where(created_by_id: Current.user.id)
                   .or(Quiz.where(classroom_id: teacher_classrooms.select(:id)))
                   .includes(:book, :classroom).order(created_at: :desc)
  end

  def show
  end

  def new
    @quiz = Quiz.new(classroom: teacher_classrooms.first, scope: :classroom)
  end

  def create
    @quiz = Quiz.new(quiz_params)
    @quiz.created_by = Current.user
    # 소유 학급만 배정 — 타 학급 id 주입 시 403(교차-학급 퀴즈 주입 방지, missions 패턴과 동일).
    @quiz.classroom = owned_classroom!(target_classroom)
    @quiz.scope = :classroom

    if @quiz.save
      generate_draft_questions(@quiz) if @quiz.book && @quiz.quiz_questions.empty?
      redirect_to edit_teacher_quiz_path(@quiz), notice: "퀴즈 초안을 만들었어요. 문항을 다듬은 뒤 게시하세요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    # classroom_id 는 수정으로 변경 불가 — 소유 퀴즈를 타 학급으로 재배정하는 경로를 차단
    # (missions#update 와 동일한 방어). 학급은 생성 시점에만 소유 검증하에 정해진다.
    if @quiz.update(quiz_params.except(:classroom_id))
      redirect_to edit_teacher_quiz_path(@quiz), notice: "퀴즈를 저장했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @quiz.destroy
    redirect_to teacher_quizzes_path, notice: "퀴즈를 삭제했어요."
  end

  private

  def set_quiz
    @quiz = Quiz.find(params[:id])
    raise Pundit::NotAuthorizedError unless owns_quiz?(@quiz)
  end

  def set_form_collections
    @classrooms = teacher_classrooms.order(:grade, :class_no).to_a
    @books = Book.order(:title).to_a
  end

  def owns_quiz?(quiz)
    Current.user.superadmin? ||
      quiz.created_by_id == Current.user.id ||
      (quiz.classroom && quiz.classroom.teacher_id == Current.user.id)
  end

  def target_classroom
    Classroom.find_by(id: quiz_params[:classroom_id]) || teacher_classrooms.first
  end

  # 도서 기반 초안 문항 생성(오프라인 폴백 내장). 학급 학년으로 눈높이(band) 반영. position 순으로 저장.
  def generate_draft_questions(quiz)
    band = ReadingDomain.band_for(quiz.classroom&.grade)
    Ai::QuizDraftService.new.call(quiz.book, band: band).each_with_index do |draft, index|
      quiz.quiz_questions.create!(
        prompt: draft[:prompt],
        choices: draft[:choices],
        answer_index: draft[:answer_index],
        position: index
      )
    end
  end

  def quiz_params
    params.require(:quiz).permit(
      :title, :book_id, :classroom_id, :published,
      quiz_questions_attributes: [ :id, :prompt, :answer_number, :position, :_destroy, { choices: [] } ]
    )
  end
end
