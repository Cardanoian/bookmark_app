class SchoolsController < ApplicationController
  skip_before_action :require_login, only: [ :search ]

  def search
    term = School.sanitize_sql_like(params[:q].to_s)
    schools = School.where("name LIKE ?", "%#{term}%").limit(10)
    render json: schools.map { |school| { id: school.id, name: school.name, region: school.region } }
  end
end
