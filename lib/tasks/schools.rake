# Reduced development seed for `schools`.
#
# The original `schools.js` (6,331 schools) is not present in this repo, so we
# seed one representative elementary school per 시도교육청 (regional education
# office). Values are synthetic but plausible. Production seeding of the full
# NEIS dataset is a later concern (see docs/IMPLEMENTATION_PLAN.md P0.7).
namespace :schools do
  desc "Seed a reduced development set of schools (one per 시도교육청 region)"
  task seed: :environment do
    schools = [
      { neis_code: "7010001", name: "서울강남초등학교",   region: "서울특별시교육청",       gu: "강남구",   office_code: "B10" },
      { neis_code: "7020001", name: "부산해운대초등학교", region: "부산광역시교육청",       gu: "해운대구", office_code: "C10" },
      { neis_code: "7030001", name: "대구수성초등학교",   region: "대구광역시교육청",       gu: "수성구",   office_code: "D10" },
      { neis_code: "7040001", name: "인천연수초등학교",   region: "인천광역시교육청",       gu: "연수구",   office_code: "E10" },
      { neis_code: "7050001", name: "광주서석초등학교",   region: "광주광역시교육청",       gu: "동구",     office_code: "F10" },
      { neis_code: "7060001", name: "대전유성초등학교",   region: "대전광역시교육청",       gu: "유성구",   office_code: "G10" },
      { neis_code: "7070001", name: "울산남부초등학교",   region: "울산광역시교육청",       gu: "남구",     office_code: "H10" },
      { neis_code: "7080001", name: "세종한솔초등학교",   region: "세종특별자치시교육청",   gu: "한솔동",   office_code: "I10" },
      { neis_code: "7090001", name: "경기수원초등학교",   region: "경기도교육청",           gu: "수원시",   office_code: "J10" },
      { neis_code: "7100001", name: "강원춘천초등학교",   region: "강원특별자치도교육청",   gu: "춘천시",   office_code: "K10" },
      { neis_code: "7110001", name: "충북청주초등학교",   region: "충청북도교육청",         gu: "청주시",   office_code: "M10" },
      { neis_code: "7120001", name: "충남천안초등학교",   region: "충청남도교육청",         gu: "천안시",   office_code: "N10" },
      { neis_code: "7130001", name: "전북전주초등학교",   region: "전북특별자치도교육청",   gu: "전주시",   office_code: "P10" },
      { neis_code: "7140001", name: "전남순천초등학교",   region: "전라남도교육청",         gu: "순천시",   office_code: "Q10" },
      { neis_code: "7150001", name: "경북포항초등학교",   region: "경상북도교육청",         gu: "포항시",   office_code: "R10" },
      { neis_code: "7160001", name: "경남창원초등학교",   region: "경상남도교육청",         gu: "창원시",   office_code: "S10" },
      { neis_code: "7170001", name: "제주제주북초등학교", region: "제주특별자치도교육청",   gu: "제주시",   office_code: "T10" }
    ]

    schools.each do |attrs|
      School.find_or_create_by!(neis_code: attrs[:neis_code]) do |school|
        school.name        = attrs[:name]
        school.region      = attrs[:region]
        school.gu          = attrs[:gu]
        school.office_code = attrs[:office_code]
      end
    end

    puts "Seeded schools. School.count = #{School.count}"
  end
end
