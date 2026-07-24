class AuditLogger
  def self.record!(actor:, action:, target: nil, request: nil, school_id: nil, classroom_id: nil, metadata: {})
    new(
      actor: actor,
      action: action,
      target: target,
      request: request,
      school_id: school_id,
      classroom_id: classroom_id,
      metadata: metadata
    ).record!
  end

  def initialize(actor:, action:, target:, request:, school_id:, classroom_id:, metadata:)
    @actor = actor
    @action = action
    @target = target
    @request = request
    @school_id = school_id
    @classroom_id = classroom_id
    @metadata = metadata
  end

  def record!
    AuditLog.create!(
      actor: @actor,
      actor_role: @actor&.role || "system",
      action: @action,
      target_type: @target&.class&.base_class&.name,
      target_id: @target&.id,
      school_id: @school_id || inferred_school_id,
      classroom_id: @classroom_id || inferred_classroom_id,
      metadata: @metadata.compact,
      ip_address: @request&.remote_ip,
      user_agent: @request&.user_agent.to_s.presence
    )
  end

  private

  def inferred_school_id
    return @target.school_id if @target&.respond_to?(:school_id)
    return @target.school&.id if @target&.respond_to?(:school)

    @actor&.school_id
  end

  def inferred_classroom_id
    return @target.classroom_id if @target&.respond_to?(:classroom_id)
    return @target.classroom&.id if @target&.respond_to?(:classroom)

    @actor&.classroom_id
  end
end
