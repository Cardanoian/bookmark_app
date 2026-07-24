require "test_helper"

# P2-3 몬스터 성장 서사 로더(docs/monsters.md §5.8 → db/seeds/monster_stories.yml).
# 24라인 전량이 3단계 장면 + 성장 메시지를 갖추고, dex_no 로 조회되는지 검증한다.
class MonsterLoreTest < ActiveSupport::TestCase
  test "covers all 24 dex lines" do
    assert_equal (1..24).to_a, MonsterLore.all.keys.sort
  end

  test "each line has three ordered scenes (stage 1,2,3) with non-blank bodies and derived titles" do
    MonsterLore.all.each_value do |story|
      assert_equal [ 1, 2, 3 ], story.scenes.map(&:stage), "dex #{story.dex_no} 는 1·2·3단계 장면을 가져야 한다"
      story.scenes.each do |scene|
        assert scene.body.present?, "dex #{story.dex_no} #{scene.stage}단계 body 는 비어 있으면 안 된다"
        assert_equal MonsterLore::SCENE_TITLES.fetch(scene.stage), scene.title
      end
    end
  end

  test "each line has a non-blank growth message" do
    MonsterLore.all.each_value do |story|
      assert story.growth_message.present?, "dex #{story.dex_no} growth_message 는 비어 있으면 안 된다"
    end
  end

  test "for returns the story for a known dex and nil for an unknown one" do
    story = MonsterLore.for(1)
    assert_equal 1, story.dex_no
    assert_equal "기·승", story.scene_for(1).title
    assert_nil story.scene_for(4)
    assert_nil MonsterLore.for(999)
  end

  test "growth messages retain the existing 해요체 reward copy at both endpoints" do
    assert_equal "한 편씩 남긴 네 생각이 길을 잃은 이야기를 다시 빛나게 해요.", MonsterLore.for(1).growth_message
    assert_equal "읽고 만나고 깊이 생각한 모든 경험은 새로운 세계를 만드는 상상이 돼요.", MonsterLore.for(24).growth_message
  end

  test "every scene body and growth message reads in polite 해요체 (smoke check)" do
    # 앱 전체 말투가 해요체로 통일됐는지 회귀 방지. 서술체(~한다)·반말(~해)만으로 쓰인 본문은
    # 존댓말 표지 '요'가 전혀 없으므로 걸러진다(세밀한 어투는 콘텐츠 리뷰가 담당).
    MonsterLore.all.each_value do |story|
      ([ story.growth_message ] + story.scenes.map(&:body)).each do |text|
        assert_includes text, "요", "dex #{story.dex_no} 본문이 해요체가 아니에요: #{text[0, 40]}"
      end
    end
  end

  test "loads the 24-line completion finale" do
    finale = MonsterLore.completion_finale

    assert_equal "스물네 개의 빛", finale.heading
    assert_equal 3, finale.paragraphs.length
    assert_includes finale.paragraphs.second, "너만의 이야기를 완성했어요"
  end
end
