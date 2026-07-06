module TeacherHelper
  # 5축 방사형(pentagon) 차트를 서버 렌더 인라인 SVG 로 반환한다(JS 차트 라이브러리 없음).
  # values: 축값 배열 또는 { axis => value } 해시(0..max). labels: 축 라벨 배열.
  # 반환 SVG 는 격자 오각형·축 스포크·데이터 <polygon>·축 라벨을 포함한다.
  def radar_chart_svg(values, labels: default_axis_labels, size: 260, max: 5.0)
    vals = radar_values(values)
    count = vals.size
    center = size / 2.0
    radius = size * 0.32
    max = max.to_f
    max = 5.0 if max <= 0

    rings = (1..4).map do |ring|
      ring_points = ring_coordinates(count, center, radius, ring / 4.0)
      tag.polygon(points: points_attr(ring_points), fill: "none", stroke: "#e5e7eb", "stroke-width" => 1)
    end

    spokes = ring_coordinates(count, center, radius, 1.0).map do |x, y|
      tag.line(x1: center, y1: center, x2: x, y2: y, stroke: "#e5e7eb", "stroke-width" => 1)
    end

    data_points = vals.each_with_index.map do |value, index|
      scale = [ value.to_f / max, 0.0 ].max
      radial_point(center, radius * scale, angle_for(index, count))
    end
    polygon = tag.polygon(points: points_attr(data_points), fill: "rgba(99,102,241,0.25)",
                          stroke: "#6366f1", "stroke-width" => 2)

    label_tags = Array(labels).each_with_index.map do |label, index|
      x, y = radial_point(center, radius + 16, angle_for(index, count))
      tag.text(label, x: x.round(1), y: y.round(1), "text-anchor" => "middle",
               "dominant-baseline" => "middle", "font-size" => 11, fill: "#4b5563")
    end

    tag.svg(
      safe_join([ *rings, *spokes, polygon, *label_tags ]),
      viewBox: "0 0 #{size} #{size}",
      width: size, height: size,
      class: "radar-chart-svg", role: "img",
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
