class Current < ActiveSupport::CurrentAttributes
  attribute :user, :classroom

  delegate :school, to: :user, allow_nil: true
end
