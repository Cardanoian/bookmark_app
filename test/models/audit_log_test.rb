require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "an audit log is append-only after creation" do
    actor = User.create!(name: "감사관리자", role: :superadmin, password: "password")
    log = AuditLog.create!(actor: actor, actor_role: actor.role, action: "admin.user_update")

    assert_predicate log, :readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { log.update!(action: "tampered") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { log.destroy! }
  end
end
