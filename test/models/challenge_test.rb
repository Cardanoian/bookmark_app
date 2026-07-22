require "test_helper"

# 챌린지 모델 검증. 소개글(description)은 미션과 대칭인 선택 입력이라 별도 검증 없이 빈 값을 허용한다.
class ChallengeTest < ActiveSupport::TestCase
  test "description 을 저장하고 다시 읽을 수 있다" do
    challenge = Challenge.create!(title: "여름 독서", scope: :global, description: "여름방학 동안 3권을 읽어요")
    assert_equal "여름방학 동안 3권을 읽어요", challenge.reload.description
  end

  test "description 은 선택 입력이라 없거나 비어 있어도 유효하다" do
    assert Challenge.new(title: "설명 없는 챌린지", scope: :global).valid?
    assert Challenge.new(title: "빈 설명 챌린지", scope: :global, description: "").valid?
    assert Challenge.new(title: "nil 설명 챌린지", scope: :global, description: nil).valid?
  end
end
