require "test_helper"

class MonstersHelperTest < ActionView::TestCase
  Species = Data.define(:key, :image_key, :name)

  test "monster_sprite renders the installed static PNG asset by default" do
    species = Species.new(key: "pup_1", image_key: "pup_1", name: "갈피멍")

    html = monster_sprite(species, img_class: "h-14 w-14")
    image = Nokogiri::HTML.fragment(html).at_css("img")

    assert_not_nil image
    assert_match %r{/(?:assets|images)/monsters/pup_1(?:-[^/.]+)?\.png}, image["src"]
    assert_equal "갈피멍", image["alt"]
    assert_equal "h-14 w-14", image["class"]
    assert_equal "lazy", image["loading"]
  end

  test "monster_sprite renders the animated WebP asset when requested" do
    species = Species.new(key: "pup_1", image_key: "pup_1", name: "갈피멍")

    html = monster_sprite(species, animated: true)
    image = Nokogiri::HTML.fragment(html).at_css("img")

    assert_not_nil image
    assert_match %r{/(?:assets|images)/monsters/pup_1(?:-[^/.]+)?\.webp}, image["src"]
  end

  test "monster_sprite falls back to the project mystery icon when the asset is missing" do
    species = Species.new(key: "pup_1", image_key: "missing-pup", name: "갈피멍")

    html = monster_sprite(species)
    assert_includes html, "#mystery"
    assert_includes html, "갈피멍"
  end

  test "monster_sprite allows image tag options to override defaults" do
    species = Species.new(key: "pup_1", image_key: "pup_1", name: "갈피멍")

    html = monster_sprite(species, alt: "", loading: "eager")
    assert_includes html, 'alt=""'
    assert_includes html, 'loading="eager"'
  end
end
