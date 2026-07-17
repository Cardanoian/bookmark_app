# 전역 퀴즈 CRUD(P7.3). 총괄이 출제하는 전역(global) 퀴즈. 문항은 중첩 폼으로 편집한다.
# 보기(choices)는 한 줄에 하나씩 입력받아 배열로 변환한다.
class Admin::QuizzesController < Admin::BaseController
  before_action :set_quiz, only: [ :show, :edit, :update, :destroy ]

  PER_PAGE = 50

  def index
    @page, @has_next_page, @quizzes = paginate(Quiz.includes(:book).order(created_at: :desc))
  end

  def show
    @questions = @quiz.quiz_questions
  end

  def new
    @quiz = Quiz.new(scope: :global)
    @quiz.quiz_questions.build
  end

  def create
    @quiz = Quiz.new(quiz_params)
    @quiz.created_by = Current.user

    if @quiz.save
      redirect_to admin_quiz_path(@quiz), notice: "‘#{@quiz.title}’ 퀴즈를 등록했어요."
    else
      @quiz.quiz_questions.build if @quiz.quiz_questions.empty?
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @quiz.quiz_questions.build if @quiz.quiz_questions.empty?
  end

  def update
    if @quiz.update(quiz_params)
      redirect_to admin_quiz_path(@quiz), notice: "퀴즈를 수정했어요."
    else
      @quiz.quiz_questions.build if @quiz.quiz_questions.empty?
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @quiz.destroy
    redirect_to admin_quizzes_path, notice: "퀴즈를 삭제했어요."
  end

  private

  def set_quiz
    @quiz = Quiz.find(params[:id])
  end

  # 보기(choices)를 줄바꿈 텍스트 → 배열로 정규화한 nested attributes.
  def quiz_params
    permitted = params.require(:quiz).permit(
      :title, :book_id, :scope, :published,
      quiz_questions_attributes: [ :id, :prompt, :choices, :answer_number, :position, :_destroy ]
    )
    normalize_choices(permitted)
    permitted
  end

  def normalize_choices(permitted)
    (permitted[:quiz_questions_attributes] || {}).each_value do |attrs|
      raw = attrs[:choices]
      next unless raw.is_a?(String)

      attrs[:choices] = raw.split("\n").map(&:strip).reject(&:blank?)
    end
  end
end
