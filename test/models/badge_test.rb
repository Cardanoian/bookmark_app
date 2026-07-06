require "test_helper"

class BadgeTest < ActiveSupport::TestCase
  test "KEYS lists the 13 badge catalog keys" do
    assert_equal 13, Badge::KEYS.size
    assert_equal 13, Badge::KEYS.uniq.size
    %w[first three ten levelA tripleA reviser grower challenger ocr
       first_evolve dex_half dex_complete final_form].each do |key|
      assert_includes Badge::KEYS, key
    end
  end

  test "key must be unique" do
    Badge.create!(key: "first", name: "첫 독후감")
    duplicate = Badge.new(key: "first", name: "중복")
    assert_not duplicate.valid?
  end

  test "key is required" do
    assert_not Badge.new(name: "이름만").valid?
  end
end
