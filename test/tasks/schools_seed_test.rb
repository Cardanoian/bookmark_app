require "test_helper"
require "rake"
require "tempfile"

# schools:seed_full 검증(계획 §1.2·§5). 소형 fixture CSV 로 배치 upsert 의 매핑·멱등·
# 입력 검증·upsert 갱신 안정성을 검증한다(전량 수천 행을 테스트 DB 에 넣지 않는다).
class SchoolsSeedTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("schools:seed_full")
    @csv = Rails.root.join("test/fixtures/files/schools_sample.csv").to_s
  end

  def seed_full!(path = @csv)
    ENV["SCHOOLS_CSV"] = path
    ENV["SCHOOLS_ALLOW_PARTIAL"] = "1"
    Rake::Task["schools:seed_full"].reenable
    capture_io { Rake::Task["schools:seed_full"].invoke }
  ensure
    ENV.delete("SCHOOLS_CSV")
    ENV.delete("SCHOOLS_ALLOW_PARTIAL")
  end

  test "CSV의 유효 행을 모두 적재한다" do
    seed_full!

    assert_equal 3, School.count
    assert School.exists?(neis_code: "7010001")
  end

  test "필수값이 비어 있으면 일부만 적재하지 않고 전체를 거부한다" do
    invalid = Tempfile.new([ "schools-invalid", ".csv" ])
    invalid.write("neis_code,name,region,gu,office_code,address\n")
    invalid.write(",코드없는학교,서울특별시교육청,중구,B10,서울특별시 중구 테스트로 3\n")
    invalid.flush

    assert_raises(Schools::SnapshotValidator::InvalidSnapshot) { seed_full!(invalid.path) }
    assert_equal 0, School.count
  ensure
    invalid&.close!
  end

  test "CSV 의 모든 컬럼을 매핑한다" do
    seed_full!

    school = School.find_by(neis_code: "7010001")
    assert_equal "서울테스트초", school.name
    assert_equal "서울특별시교육청", school.region
    assert_equal "강남구", school.gu
    assert_equal "B10", school.office_code
    assert_equal "서울특별시 강남구 테스트로 1", school.address
    assert_equal "neis", school.data_source
    assert school.active?
    assert school.synced_at.present?
  end

  test "gu 공백(세종)은 nil 로 적재된다" do
    seed_full!

    assert_nil School.find_by(neis_code: "7080001").gu
  end

  test "재실행해도 중복되지 않는다(멱등)" do
    seed_full!
    seed_full!

    assert_equal 3, School.count
  end

  test "같은 neis_code 는 새 행을 만들지 않고 제자리 갱신한다(upsert 안정)" do
    seed_full!
    assert_equal 3, School.count

    renamed = Tempfile.new([ "schools", ".csv" ])
    renamed.write("neis_code,name,region,gu,office_code,address\n")
    renamed.write("7010001,서울강남초개칭,서울특별시교육청,강남구,B10,서울특별시 강남구 새로 9\n")
    renamed.flush

    seed_full!(renamed.path)

    assert_equal 3, School.count, "기존 neis_code 갱신은 중복 행을 만들지 않는다"
    updated = School.find_by(neis_code: "7010001")
    assert_equal "서울강남초개칭", updated.name
    assert_equal "서울특별시 강남구 새로 9", updated.address
    assert_equal 1, School.active.where(data_source: "neis").count,
      "새 완전 스냅샷에 없는 기존 NEIS 학교는 삭제하지 않고 비활성화"
  ensure
    renamed&.close!
  end

  test "파일이 없으면 안내 후 no-op(크래시 없음)" do
    assert_nothing_raised do
      out, = seed_full!("/tmp/does-not-exist-#{SecureRandom.hex(4)}.csv")
      assert_match(/not found/, out)
    end
    assert_equal 0, School.count
  end

  test "사라진 NEIS 학교는 비활성화하고 수동 학교는 보존한다" do
    old = School.create!(name: "폐교예정초", neis_code: "OLD1", data_source: "neis")
    manual = School.create!(name: "수동등록초", neis_code: "MAN1", data_source: "manual")

    seed_full!

    assert_not old.reload.active?
    assert manual.reload.active?
    assert_equal "manual", manual.data_source
    assert_equal 5, School.count, "동기화에서 빠진 행도 삭제하지 않는다"
  end

  test "연결 데이터가 없는 구 합성 학교는 제거한다" do
    legacy = School.create!(name: "구합성초", neis_code: "7150001", data_source: "manual")

    seed_full!

    assert_not School.exists?(legacy.id)
  end

  test "연결 데이터가 있는 구 합성 학교는 비활성 보존한다" do
    legacy = School.create!(name: "구합성초", neis_code: "7150001", data_source: "manual")
    classroom = Classroom.create!(school: legacy, grade: 3, class_no: 1)
    User.create!(school: legacy, classroom: classroom, name: "보존학생", password: "password")

    seed_full!

    assert_not legacy.reload.active?
    assert_equal "sample", legacy.data_source
  end

  test "전국 검증이 켜져 있으면 소형 CSV 적재를 거부한다" do
    ENV["SCHOOLS_CSV"] = @csv
    ENV.delete("SCHOOLS_ALLOW_PARTIAL")
    Rake::Task["schools:seed_full"].reenable

    assert_raises(Schools::SnapshotValidator::InvalidSnapshot) do
      capture_io { Rake::Task["schools:seed_full"].invoke }
    end
    assert_equal 0, School.count
  ensure
    ENV.delete("SCHOOLS_CSV")
  end
end
