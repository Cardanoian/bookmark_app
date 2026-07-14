# 학교 시드 태스크.
#
# 세 태스크로 나뉜다(계획 §1):
#   - schools:seed       — 축소 개발 세트(17개 시도교육청 대표교). dev/test/CI 결정성·속도용.
#                          프로덕션에서는 no-op(합성 코드 오염 방지 — schools:seed_full 사용).
#   - schools:fetch      — dev 전용. NEIS 학교기본정보 OpenAPI 로 전국 초등학교를 수집해
#                          db/seeds/schools.csv 로 굽는다(네트워크 사용, 개발자가 갱신 시 수동).
#   - schools:seed_full  — db/seeds/schools.csv 를 읽어 upsert_all 로 전량 적재(오프라인·멱등).
#
# 시드는 네트워크를 타지 않는다(획득=fetch, 적재=seed_full 분리). 멱등 키는 neis_code(표준학교코드).
require "csv"

namespace :schools do
  # CSV 컬럼(seed_full 이 읽고 fetch 가 쓰는 계약). 균일 컬럼셋(upsert_all 요건).
  def schools_csv_headers
    %w[neis_code name region gu office_code address]
  end

  # db/seeds/schools.csv 경로. 테스트는 ENV["SCHOOLS_CSV"] 로 fixture 를 주입한다.
  def schools_csv_path
    ENV["SCHOOLS_CSV"].presence || Rails.root.join("db/seeds/schools.csv").to_s
  end

  desc "Seed a reduced development set of schools (one per 시도교육청 region)"
  task seed: :environment do
    if Rails.env.production?
      # 프로덕션은 전량 적재(schools:seed_full)를 쓴다. 축소 합성 세트를 심으면 seed_full 의
      # 실코드 upsert 가 지우지 못하는 고아 17행이 남으므로 여기서 실행하지 않는다(계획 §1.4).
      puts "schools:seed skipped in production — run schools:seed_full with db/seeds/schools.csv."
      next
    end

    schools = [
      { neis_code: "7010001", name: "서울강남초등학교",   region: "서울특별시교육청",       gu: "강남구",   office_code: "B10" },
      { neis_code: "7020001", name: "부산해운대초등학교", region: "부산광역시교육청",       gu: "해운대구", office_code: "C10" },
      { neis_code: "7030001", name: "대구수성초등학교",   region: "대구광역시교육청",       gu: "수성구",   office_code: "D10" },
      { neis_code: "7040001", name: "인천연수초등학교",   region: "인천광역시교육청",       gu: "연수구",   office_code: "E10" },
      { neis_code: "7050001", name: "광주서석초등학교",   region: "광주광역시교육청",       gu: "동구",     office_code: "F10" },
      { neis_code: "7060001", name: "대전유성초등학교",   region: "대전광역시교육청",       gu: "유성구",   office_code: "G10" },
      { neis_code: "7070001", name: "울산남부초등학교",   region: "울산광역시교육청",       gu: "남구",     office_code: "H10" },
      { neis_code: "7080001", name: "세종한솔초등학교",   region: "세종특별자치시교육청",   gu: nil,        office_code: "I10" },
      { neis_code: "7090001", name: "경기수원초등학교",   region: "경기도교육청",           gu: "수원시",   office_code: "J10" },
      { neis_code: "7100001", name: "강원춘천초등학교",   region: "강원특별자치도교육청",   gu: "춘천시",   office_code: "K10" },
      { neis_code: "7110001", name: "충북청주초등학교",   region: "충청북도교육청",         gu: "청주시",   office_code: "M10" },
      { neis_code: "7120001", name: "충남천안초등학교",   region: "충청남도교육청",         gu: "천안시",   office_code: "N10" },
      { neis_code: "7130001", name: "전북전주초등학교",   region: "전북특별자치도교육청",   gu: "전주시",   office_code: "P10" },
      { neis_code: "7140001", name: "전남순천초등학교",   region: "전라남도교육청",         gu: "순천시",   office_code: "Q10" },
      { neis_code: "7150001", name: "포항원동초등학교",   region: "경상북도교육청",         gu: "포항시",   office_code: "R10" },
      { neis_code: "7160001", name: "경남창원초등학교",   region: "경상남도교육청",         gu: "창원시",   office_code: "S10" },
      { neis_code: "7170001", name: "제주제주북초등학교", region: "제주특별자치도교육청",   gu: "제주시",   office_code: "T10" }
    ]

    schools.each do |attrs|
      school = School.find_or_initialize_by(neis_code: attrs[:neis_code])
      school.assign_attributes(attrs)
      school.save!
    end

    puts "Seeded schools. School.count = #{School.count}"
  end

  desc "Fetch all elementary schools from NEIS OpenAPI into db/seeds/schools.csv (dev only, requires key)"
  task fetch: :environment do
    fetcher = Schools::NeisFetcher.new
    unless fetcher.available?
      puts "schools:fetch skipped — no NEIS api_key in credentials (:neis, :api_key)."
      next
    end

    rows = fetcher.fetch_all
    if rows.empty?
      puts "schools:fetch — NEIS returned no rows (network/parse failure). CSV unchanged."
      next
    end

    CSV.open(schools_csv_path, "w") do |csv|
      csv << schools_csv_headers
      rows.each { |row| csv << schools_csv_headers.map { |header| row[header.to_sym] } }
    end

    puts "Fetched #{rows.size} elementary schools → #{schools_csv_path}"
  end

  desc "Load the full school set from db/seeds/schools.csv via upsert_all (offline, idempotent)"
  task seed_full: :environment do
    path = schools_csv_path
    unless File.exist?(path)
      puts "schools:seed_full skipped — #{path} not found (run schools:fetch first)."
      next
    end

    rows = CSV.read(path, headers: true).filter_map do |row|
      name = row["name"].to_s.strip
      next if name.blank? # upsert_all 은 AR 검증을 우회하므로 name 공백 행을 사전 제거

      # 모든 해시는 동일 컬럼 집합이어야 한다(upsert_all 균일 키 요건). 빈 값은 nil 로 정규화.
      {
        neis_code: row["neis_code"].to_s.strip,
        name: name,
        region: row["region"].to_s.strip.presence,
        gu: row["gu"].to_s.strip.presence,
        office_code: row["office_code"].to_s.strip.presence,
        address: row["address"].to_s.strip.presence
      }
    end

    rows.reject! { |r| r[:neis_code].blank? }

    if rows.empty?
      puts "schools:seed_full — no valid rows in #{path}."
      next
    end

    School.upsert_all(rows, unique_by: :neis_code, record_timestamps: true)
    puts "Loaded #{rows.size} schools from #{path}. School.count = #{School.count}"
  end
end
