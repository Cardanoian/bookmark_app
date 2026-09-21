require "test_helper"

class MultimediaCreditsTest < ActionDispatch::IntegrationTest
  CREDIT_ASSET_GLOBS = [
    "app/assets/images/**/*.{png,jpg,jpeg,gif,webp,svg,avif}",
    "app/assets/fonts/**/*.{woff,woff2,ttf,otf}",
    "app/assets/audio/**/*.{mp3,wav,ogg,m4a}",
    "app/assets/videos/**/*.{mp4,webm}",
    "public/**/*.{png,jpg,jpeg,gif,webp,svg,avif,mp3,wav,ogg,m4a,mp4,webm}"
  ].freeze

  test "multimedia credits page is publicly accessible without login" do
    get multimedia_credits_path

    assert_response :success
    assert_select "h1", text: "멀티미디어 교육자료 목록"
    assert_includes response.body, "제20회 디지털교육연구대회 보고서 [붙임 6]"
    assert_includes response.body, "Web Audio API의 오실레이터"
    assert_includes response.body, "별도의 음원 파일이 없습니다"

    # Verify table structure
    assert_select "table tbody tr", count: MultimediaCredit.all.size

    # Verify items exist
    assert_includes response.body, "pup_1.png"
    assert_includes response.body, "PretendardVariable.woff2"
    assert_includes response.body, "icon.svg"
    assert_includes response.body, "dragon_3.webp"
  end

  test "credit data matches the complete asset inventory and decimal MB sizes" do
    items = MultimediaCredit.all
    paths_by_filename = credit_asset_paths.group_by { |path| path.basename.to_s }
    duplicate_filenames = paths_by_filename.select { |_filename, paths| paths.many? }.keys

    assert_empty duplicate_filenames, "크레딧 대상 파일명은 서로 달라야 경로 없이 안전하게 대조할 수 있다"
    assert_equal (1..items.size).to_a, items.pluck(:number), "번호는 1부터 빠짐없이 이어져야 한다"
    assert_equal paths_by_filename.keys.sort, items.pluck(:filename).sort,
                 "실제 멀티미디어 파일과 크레딧 목록이 일치해야 한다"

    items.each do |item|
      path = paths_by_filename.fetch(item[:filename]).sole
      decimal_megabytes = path.size / 1_000_000.0
      expected_size = format(decimal_megabytes < 0.01 ? "%.3f" : "%.2f", decimal_megabytes)

      assert_equal expected_size, item[:size],
                   "#{item[:filename]} 크기는 decimal MB(1 MB = 1,000,000 bytes)로 기록해야 한다"
    end
  end

  test "monster image credits describe both AI generation and in-project processing" do
    monster_filenames = Rails.root.glob("app/assets/images/monsters/*.{png,webp}").map { |path| path.basename.to_s }
    monster_items = MultimediaCredit.all.select { |item| monster_filenames.include?(item[:filename]) }

    assert_equal monster_filenames.sort, monster_items.pluck(:filename).sort
    monster_items.each do |item|
      assert_equal "제작(Gemini 원본 생성 후 자체 가공)", item[:source], item[:filename]
    end
  end

  test "sessions/new footer links to multimedia credits page with oscillator notice" do
    get new_session_path

    assert_response :success
    assert_select "a[href='#{multimedia_credits_path}'][target='_blank']", text: /멀티미디어 출처 자세히 보기/
    assert_includes response.body, "Web Audio API의 오실레이터로 실시간 합성하므로 별도의 음원 파일이 없습니다"
  end

  private

  def credit_asset_paths
    CREDIT_ASSET_GLOBS.flat_map { |glob| Rails.root.glob(glob) }.sort
  end
end
