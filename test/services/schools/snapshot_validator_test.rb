require "test_helper"

class Schools::SnapshotValidatorTest < ActiveSupport::TestCase
  def row(code:, office: "B10", name: "테스트초")
    { neis_code: code, name: name, office_code: office }
  end

  test "accepts a structurally valid partial fixture when nationwide checks are disabled" do
    rows = [ row(code: "S1"), row(code: "S2") ]

    assert Schools::SnapshotValidator.new(rows).validate!(nationwide: false)
  end

  test "rejects blank required fields and duplicate NEIS codes" do
    rows = [ row(code: "S1"), row(code: "S1"), row(code: "", name: "") ]

    error = assert_raises(Schools::SnapshotValidator::InvalidSnapshot) do
      Schools::SnapshotValidator.new(rows).validate!(nationwide: false)
    end
    assert_match(/NEIS 코드가 없는 행 1개/, error.message)
    assert_match(/학교명이 없는 행 1개/, error.message)
    assert_match(/중복 NEIS 코드 1개/, error.message)
  end

  test "nationwide validation rejects a small or regionally incomplete snapshot" do
    error = assert_raises(Schools::SnapshotValidator::InvalidSnapshot) do
      Schools::SnapshotValidator.new([ row(code: "S1") ]).validate!
    end

    assert_match(/비정상적으로 적습니다/, error.message)
    assert_match(/누락 시도교육청 코드/, error.message)
  end
end
