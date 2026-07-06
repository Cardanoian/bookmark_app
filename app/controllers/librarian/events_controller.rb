# 이달의 책·행사 CRUD(P6.5). 사서의 소속 학교로만 스코프한다(경계).
class Librarian::EventsController < Librarian::BaseController
  before_action :set_event, only: [ :show, :edit, :update, :destroy ]

  def index
    @events = school_events.order(Arel.sql("event_on IS NULL, event_on DESC"))
  end

  def show
  end

  def new
    @event = LibraryEvent.new
  end

  def create
    @event = LibraryEvent.new(event_params.merge(school: current_school))

    if @event.save
      redirect_to librarian_event_path(@event), notice: "‘#{@event.title}’ 행사를 등록했어요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @event.update(event_params)
      redirect_to librarian_event_path(@event), notice: "행사를 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @event.destroy
    redirect_to librarian_events_path, notice: "행사를 삭제했어요."
  end

  private

  # 자기 학교 행사만. 타학교 이벤트 접근 시 not found → 404(경계).
  def school_events
    LibraryEvent.where(school_id: current_school&.id)
  end

  def set_event
    @event = school_events.find(params[:id])
  end

  def event_params
    params.require(:library_event).permit(:title, :description, :event_on, :book_id)
  end
end
