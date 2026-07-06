# 사서 대시보드(P6.5). 전교 독서 현황 + 인기대출(학교 + 전국 NULL) + 이달의 책·행사.
class Librarian::DashboardsController < Librarian::BaseController
  def show
    @school = current_school
    classroom_ids = @school ? @school.classrooms.select(:id) : []

    @report_count = Report.where(classroom_id: classroom_ids).count
    @reader_count = Report.where(classroom_id: classroom_ids).distinct.count(:user_id)

    @loans = LibraryLoan.where(school_id: [ @school&.id, nil ].uniq)
                        .order(count: :desc).limit(10).to_a
    @events = LibraryEvent.where(school_id: @school&.id)
                          .order(Arel.sql("event_on IS NULL, event_on DESC")).to_a
  end
end
