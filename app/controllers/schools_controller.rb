class SchoolsController < ApplicationController
  skip_before_action :require_login, only: [ :search ]
  # 학교 자동완성 — 가입/로그인 폼에서 쓰는 공개 조회(민감 데이터 없음).
  skip_after_action :verify_authorized

  def search
    term = School.sanitize_sql_like(params[:q].to_s)
    schools = School.where("name LIKE ?", "%#{term}%").limit(10)
    render json: schools.map { |school| { id: school.id, name: school.name, region: school.region } }
  end
end
