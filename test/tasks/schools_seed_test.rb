require "test_helper"
require "rake"
require "tempfile"

# schools:seed_full 검증(계획 §1.2·§5). 소형 fixture CSV 로 배치 upsert 의 매핑·멱등·
# name 공백 필터·upsert 갱신 안정성을 검증한다(전량 6,300행을 테스트 DB 에 넣지 않는다).
class SchoolsSeedTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("schools:seed_full")
    @csv = Rails.root.join("test/fixtures/files/schools_sample.csv").to_s
  end

  def seed_full!(path = @csv)
    ENV["SCHOOLS_CSV"] = path
    Rake::Task["schools:seed_full"].reenable
    capture_io { Rake::Task["schools:seed_full"].invoke }
  ensure
    ENV.delete("SCHOOLS_CSV")
  end

  test "유효 행만 적재하고 name/neis_code 공백 행은 건너뛴다" do
    seed_full!

    assert_equal 3, School.count, "코드공백·이름공백 2행은 제외"
    assert School.exists?(neis_code: "7010001")
    assert_not School.exists?(name: "코드없는학교"), "neis_code 공백 행은 적재되지 않는다"
    assert_not School.exists?(office_code: "J10"), "name 공백 행(7090001)은 적재되지 않는다"
  end

  test "CSV 의 모든 컬럼을 매핑한다" do
    seed_full!

    school = School.find_by(neis_code: "7010001")
    assert_equal "서울테스트초", school.name
    assert_equal "서울특별시교육청", school.region
    assert_equal "강남구", school.gu
    assert_equal "B10", school.office_code
    assert_equal "서울특별시 강남구 테스트로 1", school.address
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
end
