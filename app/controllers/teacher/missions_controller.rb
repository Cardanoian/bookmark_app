# 교사 미션 관리(P6.2). 담임 학급 독서 미션 CRUD(제목·도서·기간).
class Teacher::MissionsController < Teacher::BaseController
  before_action :set_mission, only: [ :show, :edit, :update, :destroy ]
  before_action :set_classrooms, only: [ :new, :create, :edit, :update ]

  def index
    @missions = Mission.where(classroom_id: teacher_classrooms.select(:id))
                       .includes(:book, :classroom).order(created_at: :desc)
  end

  def show
  end

  def new
    @mission = Mission.new(classroom: teacher_classrooms.first)
  end

  def create
    classroom = owned_classroom!(target_classroom)
    @mission = Mission.new(mission_params.except(:classroom_id).merge(classroom: classroom))

    if @mission.save
      redirect_to teacher_mission_path(@mission), notice: "‘#{@mission.title}’ 미션을 만들었어요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @mission.update(mission_params.except(:classroom_id))
      redirect_to teacher_mission_path(@mission), notice: "미션을 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mission.destroy
    redirect_to teacher_missions_path, notice: "미션을 삭제했어요."
  end

  private

  def set_mission
    @mission = Mission.find(params[:id])
    owned_classroom!(@mission.classroom)
  end

  def set_classrooms
    @classrooms = teacher_classrooms.order(:grade, :class_no).to_a
  end

  def target_classroom
    Classroom.find_by(id: mission_params[:classroom_id]) || teacher_classrooms.first
  end

  def mission_params
    params.require(:mission).permit(:title, :book_id, :start_date, :end_date, :classroom_id)
  end
end
