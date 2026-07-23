class Admin::AuditLogsController < Admin::BaseController
  PER_PAGE = 50

  def index
    scope = AuditLog.includes(:actor).recent_first
    scope = scope.where(action: params[:action]) if AuditLog::ACTION_LABELS.key?(params[:action])
    scope = scope.where(actor_id: params[:actor_id]) if params[:actor_id].present?
    scope = scope.where("created_at >= ?", parsed_date(params[:from])&.beginning_of_day) if parsed_date(params[:from])
    scope = scope.where("created_at <= ?", parsed_date(params[:to])&.end_of_day) if parsed_date(params[:to])

    @page, @has_next_page, @audit_logs = paginate(scope)
    @actions = AuditLog::ACTION_LABELS
  end

  private

  def parsed_date(value)
    return if value.blank?

    Date.iso8601(value)
  rescue Date::Error
    nil
  end
end
