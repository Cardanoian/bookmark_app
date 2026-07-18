class SchoolsController < ApplicationController
  skip_before_action :require_login, only: [ :search, :gus, :classrooms ]
  # 학교/학급 자동완성·캐스케이딩 — 가입/로그인 폼에서 쓰는 공개 조회(민감 데이터 없음).
  skip_after_action :verify_authorized

  # 이름검색(q) + 시도/시군구(region/gu) 필터 → 학교 목록 JSON. 전량 select 를 대체하는
  # 스케일-세이프 조회(계획 §2.4). 결과는 상한(100)해 페이로드를 봉인한다.
  def search
    scope = School.active
    if params[:q].present?
      term = School.sanitize_sql_like(params[:q].to_s)
      scope = scope.where("name LIKE ?", "%#{term}%")
    end
    scope = scope.where(region: params[:region]) if params[:region].present?
    scope = scope.where(gu: params[:gu]) if params[:gu].present?

    schools = scope.order(:name).limit(100)
    render json: schools.map { |school|
      { id: school.id, name: school.name, region: school.region, gu: school.gu }
    }
  end

  # 캐스케이딩 2단계 — 선택 시도(region)의 시군구 목록(빈 gu 제외).
  def gus
    return render(json: []) if params[:region].blank?

    list = School.active.where(region: params[:region]).where.not(gu: [ nil, "" ]).distinct.order(:gu).pluck(:gu)
    render json: list
  end

  # 로그인 폼 종속 드롭다운 — 선택 학교의 학급만 조회(전국 전량 로드 제거, 계획 §2.2).
  def classrooms
    school = School.find_by(id: params[:id])
    rooms = school ? school.classrooms.order(:grade, :class_no) : []
    render json: rooms.map { |classroom| { id: classroom.id, label: classroom.label } }
  end
end
