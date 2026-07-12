# 학교 관리(P7.2). 총괄관리자의 학교 등록·수정·삭제 전역 CRUD.
class Admin::SchoolsController < Admin::BaseController
  before_action :set_school, only: [ :show, :edit, :update, :destroy ]

  PER_PAGE = 50

  def index
    scope = School.order(:name)
    scope = scope.where("name LIKE ?", "%#{School.sanitize_sql_like(params[:q])}%") if params[:q].present?
    @page, @has_next_page, @schools = paginate(scope)
  end

  def show
  end

  def new
    @school = School.new
  end

  def create
    @school = School.new(school_params)

    if @school.save
      redirect_to admin_school_path(@school), notice: "‘#{@school.name}’ 학교를 등록했어요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @school.update(school_params)
      redirect_to admin_school_path(@school), notice: "학교 정보를 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @school.destroy
    redirect_to admin_schools_path, notice: "학교를 삭제했어요."
  end

  private

  def set_school
    @school = School.find(params[:id])
  end

  def school_params
    params.require(:school).permit(:name, :neis_code, :region, :gu, :office_code)
  end
end
