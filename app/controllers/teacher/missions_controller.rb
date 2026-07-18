# 교사 미션 관리(menu_refactor 심화 PR4). 기간·정량목표·보상 draft 를 만들고 발행(자동 배정)한다.
# 발행 후에는 제목·설명만 수정 가능(목표·기간·보상·학급 잠금). 삭제는 draft 만.
class Teacher::MissionsController < Teacher::BaseController
  before_action :set_mission, only: [ :show, :edit, :update, :destroy, :publish ]
  before_action :set_classrooms, only: [ :new, :create, :edit, :update ]

  GOAL_TYPES = %w[approved_reports game_plays].freeze

  def index
    scope = Mission.where(classroom_id: teacher_classrooms.select(:id)).includes(:classroom, :mission_goals)
    scope = scope.where(status: Mission.statuses[params[:status]]) if Mission.statuses.key?(params[:status])
    @missions = scope.order(created_at: :desc)
    @status_filter = params[:status]
  end

  def show
    @participations = @mission.mission_participations.includes(:user).to_a
    @progress = Missions::ProgressCalculator.batch(@mission, participations: @participations)
  end

  def new
    @mission = Mission.new(classroom: teacher_classrooms.first, reward_points: 50)
  end

  def create
    classroom = owned_classroom!(target_classroom)
    @mission = Mission.new(mission_params.except(:classroom_id).merge(classroom: classroom))
    apply_goals(@mission)

    if @mission.save
      redirect_to teacher_mission_path(@mission), notice: "‘#{@mission.title}’ 미션 초안을 만들었어요. 확인 후 발행하세요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    return if @mission.draft?

    # 발행 후에는 제목·설명만 수정(잠금 정책). 목표·기간은 읽기 전용으로 표시.
    flash.now[:notice] = "발행된 미션은 제목·설명만 수정할 수 있어요."
  end

  def update
    if @mission.draft?
      @mission.assign_attributes(mission_params.except(:classroom_id))
      apply_goals(@mission)
    else
      # 발행 후: 제목·설명 오탈자만 허용(목표·기간·보상·학급 잠금).
      @mission.assign_attributes(mission_params.slice(:title, :description))
    end

    if @mission.save
      redirect_to teacher_mission_path(@mission), notice: "미션을 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # draft → published 전환 + 학급 학생 자동 배정(Mission#publish! → AssignmentSync).
  def publish
    if @mission.publish!
      redirect_to teacher_mission_path(@mission), notice: "‘#{@mission.title}’ 미션을 발행했어요. 학급 학생에게 배정됐어요."
    else
      redirect_to teacher_mission_path(@mission), alert: publish_error(@mission)
    end
  end

  def destroy
    return redirect_to teacher_mission_path(@mission), alert: "발행된 미션은 삭제할 수 없어요(취소만 가능)." unless @mission.draft?

    @mission.destroy
    redirect_to teacher_missions_path, notice: "미션 초안을 삭제했어요."
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
    params.require(:mission).permit(:title, :description, :start_date, :end_date, :reward_points, :classroom_id)
  end

  # 고정 2목표(승인 독후감·게임) 폼 입력 → mission_goals 재구성. target 이 양수인 종류만 목표로 만든다.
  # draft 만 목표를 바꾼다(발행 후 update 는 이 경로를 타지 않음).
  def apply_goals(mission)
    mission.mission_goals.destroy_all if mission.persisted?
    mission.mission_goals.reset
    GOAL_TYPES.each do |goal_type|
      target = params.dig(:mission, :goals, goal_type).to_i
      mission.mission_goals.build(goal_type: goal_type, target_count: target) if target.positive?
    end
  end

  def publish_error(mission)
    if mission.mission_goals.empty?
      "발행하려면 목표를 1개 이상 추가하세요."
    elsif !mission.draft?
      "이미 발행됐거나 발행할 수 없는 상태예요."
    else
      mission.errors.full_messages.to_sentence.presence || "미션을 발행할 수 없어요."
    end
  end
end
