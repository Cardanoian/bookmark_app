require "test_helper"

class TeacherHelperTest < ActionView::TestCase
  test "radar_chart_svg renders an svg with a data polygon" do
    svg = radar_chart_svg({ content: 5, emotion: 4, life: 3, structure: 2, spelling: 1 })

    assert_includes svg, "<svg"
    assert_includes svg, "<polygon"
    assert_includes svg, "viewBox"
  end

  test "radar_chart_svg accepts an array of values" do
    svg = radar_chart_svg([ 5, 5, 5, 5, 5 ])
    assert_includes svg, "<polygon"
  end

  test "radar_chart_svg renders axis labels" do
    svg = radar_chart_svg({ content: 1, emotion: 1, life: 1, structure: 1, spelling: 1 })
    assert_includes svg, ReadingDomain::AXIS_LABELS[:content]
  end
end
