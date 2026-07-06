# 교사 루브릭 가중치 설정(P6.2). classroom.rubric_config 의 5축 가중치·강조·라벨을 수정.
# 가중치는 Classroom#rubric_weights → RubricScorable 채점에 반영된다.
class Teacher::RubricConfigsController < Teacher::BaseController
  before_action :set_classroom

  def edit
    @weights = @classroom.rubric_weights
  end

  def update
    if @classroom.update(rubric_config: build_config)
      redirect_to edit_teacher_rubric_config_path(classroom_id: @classroom.id),
                  notice: "루브릭 가중치를 저장했어요."
    else
      @weights = @classroom.rubric_weights
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_classroom
    @classroom = owned_classroom!(Classroom.find_by(id: params[:classroom_id]) || teacher_classrooms.first)
  end

  # 폼 입력을 안전한 rubric_config 해시로. 가중치는 0..5 정수로 클램프(합 0 이면 기본값).
  def build_config
    weights = ReadingDomain::RUBRIC_AXES.index_with do |axis|
      params.dig(:rubric_config, :weights, axis).to_i.clamp(0, 5)
    end
    weights = ReadingDomain::DEFAULT_RUBRIC_WEIGHTS.dup if weights.values.sum.zero?

    {
      "weights" => weights.stringify_keys,
      "emphasis" => params.dig(:rubric_config, :emphasis).presence,
      "label" => params.dig(:rubric_config, :label).presence
    }
  end
end
