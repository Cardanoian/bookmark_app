# 뱃지 카탈로그(13종) + 상점 아이템(먹이/진화의 돌/장식) 시드. 멱등(find_or_initialize_by).
namespace :badges do
  desc "Seed the 13 badge catalog entries"
  task seed: :environment do
    catalog = {
      "first"        => { name: "첫 독후감",     icon: "🌱", condition_desc: "독후감 1편 작성" },
      "three"        => { name: "독서 삼세판",   icon: "📗", condition_desc: "독후감 3편 달성" },
      "ten"          => { name: "열 권의 힘",     icon: "📚", condition_desc: "독후감 10편 달성" },
      "levelA"       => { name: "첫 A등급",       icon: "🅰️", condition_desc: "A등급 첨삭 1회" },
      "tripleA"      => { name: "트리플 A",       icon: "🏅", condition_desc: "A등급 첨삭 3회" },
      "reviser"      => { name: "고쳐쓰기 달인", icon: "✍️", condition_desc: "고쳐쓰기로 향상 1회" },
      "grower"       => { name: "쑥쑥 성장",     icon: "🌿", condition_desc: "고쳐쓰기로 점수 향상" },
      "challenger"   => { name: "도전자",         icon: "🔥", condition_desc: "챌린지 1회 참여" },
      "ocr"          => { name: "손글씨 마법사", icon: "🖋️", condition_desc: "손글씨(OCR) 독후감 제출" },
      "first_evolve" => { name: "첫 진화",       icon: "✨", condition_desc: "몬스터를 처음 진화시킴" },
      "dex_half"     => { name: "도감 절반",     icon: "🔖", condition_desc: "도감 12/24 수집" },
      "dex_complete" => { name: "도감 완성",     icon: "👑", condition_desc: "도감 24/24 수집" },
      "final_form"   => { name: "완전체",         icon: "🐲", condition_desc: "완전형 몬스터 달성" }
    }

    catalog.each do |key, attrs|
      badge = Badge.find_or_initialize_by(key: key)
      badge.name = attrs[:name]
      badge.icon = attrs[:icon]
      badge.condition_desc = attrs[:condition_desc]
      badge.save!
    end

    puts "Seeded badges. Badge.count = #{Badge.count}"
  end
end
