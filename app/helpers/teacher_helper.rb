module TeacherHelper
  RADAR_GRID = "#e0e2e8".freeze         # --color-hairline
  RADAR_LINE = "#4262ff".freeze         # --color-brand-blue
  RADAR_FILL = "rgba(66,98,255,0.16)".freeze
  RADAR_COMPARE_LINE = "#8e91a0".freeze # --color-stone (지난 기록 점선)

  # 5축 방사형(pentagon) 차트를 서버 렌더 인라인 SVG 로 반환한다(JS 차트 라이브러리 없음).
  # values: 축값 배열 또는 { axis => value } 해시(0..max). labels: 축 라벨 배열.
  # compare: 같은 형식의 비교 계열(지난 기록) — 주면 회색 점선 폴리곤을 뒤에 덧그린다.
  # 반환 SVG 는 격자 오각형·축 스포크·비교 <polygon>·데이터 <polygon>·꼭짓점 점·축 라벨을 포함한다.
  def radar_chart_svg(values, labels: default_axis_labels, size: 260, max: 5.0, compare: nil,
                      aria_label: "5축 첨삭 결과 방사형 차트")
    vals = radar_values(values)
    count = vals.size
    center = size / 2.0
    radius = size * 0.32
    max = max.to_f
    max = 5.0 if max <= 0

    rings = (1..4).map do |ring|
      ring_points = ring_coordinates(count, center, radius, ring / 4.0)
      tag.polygon(points: points_attr(ring_points), fill: "none", stroke: RADAR_GRID, "stroke-width" => 1)
    end

    spokes = ring_coordinates(count, center, radius, 1.0).map do |x, y|
      tag.line(x1: center, y1: center, x2: x, y2: y, stroke: RADAR_GRID, "stroke-width" => 1)
    end

    compare_polygon = if compare.present?
      tag.polygon(points: points_attr(radar_points(radar_values(compare), center, radius, max, count)),
                  fill: "none", stroke: RADAR_COMPARE_LINE, "stroke-width" => 1.5,
                  "stroke-dasharray" => "4 3")
    end

    data_points = radar_points(vals, center, radius, max, count)
    polygon = tag.polygon(points: points_attr(data_points), fill: RADAR_FILL,
                          stroke: RADAR_LINE, "stroke-width" => 2, "stroke-linejoin" => "round")
    dots = data_points.map { |x, y| tag.circle(cx: x, cy: y, r: 3.5, fill: RADAR_LINE) }

    label_tags = Array(labels).each_with_index.map do |label, index|
      x, y = radial_point(center, radius + 18, angle_for(index, count))
      tag.text(label, x: x.round(1), y: y.round(1), "text-anchor" => "middle",
               "dominant-baseline" => "middle", "font-size" => 12, fill: "#555a6a")
    end

    tag.svg(
      safe_join([ *rings, *spokes, compare_polygon, polygon, *dots, *label_tags ].compact),
      viewBox: "0 0 #{size} #{size}",
      width: size, height: size,
      class: "radar-chart-svg", role: "img", "aria-label" => aria_label,
      xmlns: "http://www.w3.org/2000/svg"
    )
  end

  private

  def default_axis_labels
    ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
  end

  # Hash({axis => v}) 또는 Array 를 RUBRIC_AXES 순서의 Float 배열로 정규화.
  def radar_values(values)
    if values.is_a?(Hash)
      ReadingDomain::RUBRIC_AXES.map { |axis| values[axis].to_f }
    else
      Array(values).map(&:to_f)
    end
  end

  # 정규화된 축값 배열을 차트 좌표(꼭짓점) 배열로 변환.
  def radar_points(vals, center, radius, max, count)
    vals.first(count).each_with_index.map do |value, index|
      scale = [ value.to_f / max, 0.0 ].max
      radial_point(center, radius * scale, angle_for(index, count))
    end
  end

  def angle_for(index, count)
    (-90 + index * (360.0 / count)) * Math::PI / 180
  end

  def radial_point(center, distance, angle)
    [ (center + distance * Math.cos(angle)).round(2), (center + distance * Math.sin(angle)).round(2) ]
  end

  def ring_coordinates(count, center, radius, fraction)
    (0...count).map { |index| radial_point(center, radius * fraction, angle_for(index, count)) }
  end

  def points_attr(points)
    points.map { |x, y| "#{x},#{y}" }.join(" ")
  end
end
