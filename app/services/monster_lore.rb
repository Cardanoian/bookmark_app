# 반려 몬스터 성장 서사(docs/monsters.md §5.7)를 앱 표시용으로 로드하는 리더(P2-3).
#
# 서사는 학생이 몬스터에 공감하도록 상세 화면에 보여 주는 정적 표현 콘텐츠다.
# DB 시드(monster_species)가 아니라 런타임에 YAML(db/seeds/monster_stories.yml)을
# 한 번 읽어 메모이즈한다 — MonsterSeeder 의 YAML.load_file 관행과 동일하며,
# 이 문서는 마이그레이션·스키마 변경 없이 파일만 갱신하면 되는 순수 콘텐츠다.
#
# 각 라인(dex_no)은 진화 3단계와 1:1로 대응하는 3개 장면(처음 만남·첫 성장·완전 성장)과
# 라인 전체를 요약하는 성장 메시지 한 줄로 구성된다.
class MonsterLore
  SEED_PATH = Rails.root.join("db/seeds/monster_stories.yml")

  # stage → 장면 제목(진화 단계와 1:1). YAML 은 body 만 담고 제목은 여기서 파생한다.
  SCENE_TITLES = { 1 => "처음 만남", 2 => "첫 성장", 3 => "완전 성장" }.freeze

  Scene = Struct.new(:stage, :title, :body, keyword_init: true)

  Story = Struct.new(:dex_no, :growth_message, :scenes, keyword_init: true) do
    # 특정 진화 단계(1~3)의 장면. 없으면 nil.
    def scene_for(stage)
      scenes.find { |scene| scene.stage == stage.to_i }
    end
  end

  class << self
    # dex_no 라인의 서사. 정의가 없으면 nil(뷰가 가드해 티저만 노출).
    def for(dex_no)
      all[dex_no.to_i]
    end

    # dex_no => Story 해시. 첫 호출에서 YAML 을 읽어 메모이즈(정적 콘텐츠).
    def all
      @all ||= load_stories.freeze
    end

    # 콘텐츠 파일을 다시 읽어야 할 때(예: 콘솔·테스트) 메모이즈 초기화.
    def reload!
      @all = nil
      all
    end

    private

    def load_stories
      YAML.load_file(SEED_PATH).fetch("stories").each_with_object({}) do |entry, memo|
        dex_no = entry.fetch("dex_no").to_i
        scenes = entry.fetch("scenes").map do |raw|
          stage = raw.fetch("stage").to_i
          Scene.new(stage: stage, title: SCENE_TITLES.fetch(stage), body: raw.fetch("body").to_s.strip)
        end.sort_by(&:stage)

        memo[dex_no] = Story.new(
          dex_no: dex_no,
          growth_message: entry.fetch("growth_message").to_s.strip,
          scenes: scenes
        )
      end
    end
  end
end
