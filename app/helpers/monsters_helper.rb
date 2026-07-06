# 몬스터 도감 표시 헬퍼(이모지 스프라이트·속성 라벨/색). 시드 이미지 자산이 없어 이모지로 대체한다.
module MonstersHelper
  EMOJI = {
    "pup" => "🐶", "cat" => "🐱", "hedgehog" => "🦔", "parrot" => "🦜",
    "pencil" => "✏️", "fox" => "🦊", "owl" => "🦉", "robot" => "🤖",
    "turtle" => "🐢", "hamster" => "🐹", "whale" => "🐳", "rabbit" => "🐰",
    "deer" => "🦌", "bear" => "🐻", "chick" => "🐤", "penguin" => "🐧",
    "dino" => "🦖", "frog" => "🐸", "squirrel" => "🐿️", "mushroom" => "🍄",
    "unicorn" => "🦄", "butterfly" => "🦋", "dokkaebi" => "👺", "dragon" => "🐲"
  }.freeze

  ELEMENT_LABELS = {
    "story" => "이야기", "knowledge" => "지식", "emotion" => "감정",
    "adventure" => "모험", "nature" => "자연", "imagination" => "상상"
  }.freeze

  ELEMENT_CLASSES = {
    "story" => "bg-purple-100 text-purple-700",
    "knowledge" => "bg-sky-100 text-sky-700",
    "emotion" => "bg-pink-100 text-pink-700",
    "adventure" => "bg-orange-100 text-orange-700",
    "nature" => "bg-green-100 text-green-700",
    "imagination" => "bg-amber-100 text-amber-700"
  }.freeze

  # 종(또는 key) → 대표 이모지. 미지정이면 알 이모지.
  def monster_emoji(species_or_key)
    key = species_or_key.respond_to?(:key) ? species_or_key.key : species_or_key.to_s
    EMOJI[key.to_s.sub(/_\d+\z/, "")] || "🥚"
  end

  def element_label(element)
    ELEMENT_LABELS[element.to_s] || element.to_s
  end

  def element_badge_classes(element)
    ELEMENT_CLASSES[element.to_s] || "bg-gray-100 text-gray-700"
  end

  CONDITION_LABELS = {
    "points" => "포인트", "reports" => "독후감", "a_grades" => "A등급", "b_or_better" => "B등급 이상",
    "distinct_genres" => "장르 수", "classics" => "고전", "revisions" => "고쳐쓰기", "streak_days" => "연속 제출일",
    "missions" => "미션", "challenges" => "챌린지", "quizzes" => "퀴즈", "topic_posts" => "토론 글",
    "cheers_received" => "받은 응원", "dex_count" => "도감 수집", "badge" => "뱃지"
  }.freeze

  def condition_label(key)
    CONDITION_LABELS[key.to_s] || key.to_s
  end

  # 진화 조건 한 항목의 현재 진행값(ReadingStats 대비). badge 는 보유 여부(0/1).
  def condition_progress(stats, key, target)
    if key.to_s == "badge"
      stats.badge?(target) ? 1 : 0
    elsif stats.respond_to?(key)
      stats.public_send(key)
    else
      0
    end
  end
end
