# 몬스터 도감(종·진화 규칙) CRUD(P7.3). element/rarity enum, evolves_from_id(진화 규칙),
# evolve_condition(JSON) 을 안전하게 편집한다. 진화체인 무결성은 모델 검증이 담당한다.
class Admin::MonsterSpeciesController < Admin::BaseController
  before_action :set_species, only: [ :show, :edit, :update, :destroy ]

  def index
    @species = MonsterSpecies.order(:dex_no, :stage)
  end

  def show
  end

  def new
    @species_record = MonsterSpecies.new
  end

  def create
    @species_record = MonsterSpecies.new(species_params)

    if @species_record.save
      redirect_to admin_monster_species_path(@species_record), notice: "‘#{@species_record.name}’ 몬스터를 등록했어요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @species_record.update(species_params)
      redirect_to admin_monster_species_path(@species_record), notice: "몬스터 정보를 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @species_record.destroy
    redirect_to admin_monster_species_index_path, notice: "몬스터를 삭제했어요."
  end

  private

  def set_species
    @species_record = MonsterSpecies.find(params[:id])
  end

  def species_params
    params.require(:monster_species).permit(
      :key, :name, :dex_no, :stage, :element, :rarity,
      :evolves_from_id, :evolve_condition_json, :image_key, :description
    )
  end
end
