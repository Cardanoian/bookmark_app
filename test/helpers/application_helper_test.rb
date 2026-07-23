require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "ui_icon renders a decorative symbol from the shared SVG sprite" do
    html = ui_icon(:books, class_name: "h-6 w-6")

    assert_includes html, "ui-icons"
    assert_includes html, "#books"
    assert_includes html, "aria-hidden=\"true\""
    assert_includes html, "h-6 w-6"
  end

  test "sticker_icon maps persisted emoji values to project icons" do
    assert_includes sticker_icon("👍"), "#like"
    assert_includes sticker_icon("🌟"), "#star"
  end

  test "empty_state_image maps related states to the same generated illustration" do
    assert_equal "empty_states/empty-ranking.png", empty_state_image(:school)
    assert_equal empty_state_image(:school), empty_state_image(:graduation)
    assert_equal "empty_states/sequel-writing.png", empty_state_image(:writing)
    assert_equal "empty_states/empty-inbox.png", empty_state_image(:unknown)
  end
end
