require "test_helper"

# 올린 사진은 촬영 정보(촬영 일시·기기·위치)를 지운 사본만 저장한다(2026-11-11). 지우지 못하면 실패다 —
# 원본으로 이어 가지 않는다. 진짜 libvips 가 필요한 테스트는 libvips 없는 개발기에서 건너뛴다(CI 에서 돈다).
class PhotoSanitizerTest < ActiveSupport::TestCase
  teardown { @tempfiles&.each(&:close!) }

  # 문자열(direct upload 로 미리 올린 blob 의 signed id)은 이미 저장된 원본이고, 해시는 요청으로 들어온 파일이 아니다.
  test "refuses anything that is not an uploaded file" do
    [ "eyJfcmFpbHMiOnsi-signed-blob-id", { io: StringIO.new("x"), filename: "a.jpg" }, nil ].each do |value|
      error = assert_raises(PhotoSanitizer::Failed) { PhotoSanitizer.call(value) }
      assert_includes error.message, value.class.name
    end
  end

  test "refuses a photo over the attachment limit before decoding it" do
    decoded = false
    sanitizer = PhotoSanitizer.new
    sanitizer.define_singleton_method(:encode) { |_file| decoded = true }

    error = assert_raises(PhotoSanitizer::TooLarge) { sanitizer.call(uploaded("x" * (Report::IMAGE_MAX_BYTES + 1))) }

    assert_includes error.message, "larger than"
    assert_not decoded, "한도를 넘은 사진은 풀지 않는다"
  end

  # 저장 검증은 다시 쓴 JPEG 만 보므로, 여기서 막지 않으면 libvips 가 읽는 모든 형식(PDF·SVG 등)이 사진이 된다.
  # 판별은 매직바이트 우선이라 이름만 사진처럼 바꾼 파일도 걸린다. libvips 없이도 돈다.
  test "refuses a file that is not a camera photo format, even when named like one" do
    { "%PDF-1.4\n%fake".b => "IMG_0001.png",
      %(<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>) => "IMG_0002.jpg" }.each do |bytes, name|
      error = assert_raises(PhotoSanitizer::Failed) { PhotoSanitizer.call(uploaded(bytes, filename: name)) }

      assert_includes error.message, "not a camera photo format", name
    end
  end

  # 진짜 이미지가 아니면(libvips 가 없는 호스트에서는 LoadError) 원본을 남기지 않고 실패한다.
  test "a file that cannot be re-encoded fails instead of being kept as is" do
    error = assert_raises(PhotoSanitizer::Failed) { PhotoSanitizer.call(uploaded("fake-image-bytes")) }

    assert_includes error.message, "could not be re-encoded"
  end

  test "keeps a JPEG without the camera information, turned the right way up" do
    require_libvips!

    result = PhotoSanitizer.call(uploaded(jpeg_with_exif(width: 64, height: 48, orientation: 6),
                                          filename: "IMG_20261111_093000.jpg"))
    bytes = result[:io].read
    image = Vips::Image.new_from_buffer(bytes, "")

    assert_nil bytes.index("Exif\x00\x00".b), "다시 쓴 사진에 EXIF 가 남아 있으면 안 된다"
    assert_empty image.get_fields.grep(/\A(exif|xmp|iptc)-/)
    # 방향 정보(Orientation 6 = 오른쪽으로 90도)를 지우기 전에 돌려 세워야 옆으로 누운 사진이 남지 않는다.
    assert_equal [ 48, 64 ], [ image.width, image.height ]
    assert_equal "photo.jpg", result[:filename], "촬영 일시가 든 파일 이름도 남기지 않는다"
    assert_equal "image/jpeg", result[:content_type]
    assert_equal "image/jpeg", Marcel::MimeType.for(StringIO.new(bytes))
  end

  # 10MB 안에도 수억 화소를 넣을 수 있다 — 머리만 읽고 화소 한도를 넘으면 풀지 않는다.
  test "refuses a photo with too many pixels without decoding it" do
    require_libvips!
    decoded = false
    sanitizer = PhotoSanitizer.new(max_pixels: (64 * 48) - 1)
    sanitizer.define_singleton_method(:encode) { |_file| decoded = true }

    error = assert_raises(PhotoSanitizer::TooLarge) { sanitizer.call(uploaded(jpeg_with_exif)) }

    assert_includes error.message, "pixels"
    assert_not decoded
  end

  # JPEG 에는 투명이 없다 — 투명 배경에 검은 글씨인 화면 캡처·스캔이 검은 바탕이 되면 글씨가 사라진다.
  test "fills transparent areas with white" do
    require_libvips!
    transparent = Vips::Image.black(32, 32).bandjoin(0).copy(interpretation: :b_w).pngsave_buffer

    image = Vips::Image.new_from_buffer(PhotoSanitizer.call(uploaded(transparent, filename: "scan.png"))[:io].read, "")

    assert_operator image.avg, :>, 250, "투명한 부분은 흰 바탕이어야 한다"
  end

  test "shrinks a large photo to the stored size limit" do
    require_libvips!
    jpeg = (Vips::Image.black(3000, 1000) + 128).cast(:uchar).jpegsave_buffer

    image = Vips::Image.new_from_buffer(PhotoSanitizer.call(uploaded(jpeg))[:io].read, "")

    assert_equal PhotoSanitizer::MAX_EDGE, [ image.width, image.height ].max
  end

  # image_processing 은 saver 가 모르는 옵션을 예외 없이 버린다 — `strip` 이 조용히 무시돼 정보가 남은 결과도
  # 저장하지 않는다. 인코딩만 대역으로 바꿔 사후 검사가 실제 경로에 걸려 있는지 본다.
  test "a re-encode that still carries EXIF is refused" do
    require_libvips!
    leaked = jpeg_with_exif
    sanitizer = PhotoSanitizer.new
    sanitizer.define_singleton_method(:encode) { |_file| leaked }

    error = assert_raises(PhotoSanitizer::Failed) { sanitizer.call(uploaded(leaked)) }

    assert_includes error.message, "exif-data"
  end

  private

  def uploaded(bytes, filename: "IMG_0001.jpg")
    file = Tempfile.new([ "upload", File.extname(filename) ], binmode: true)
    (@tempfiles ||= []) << file
    file.write(bytes)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: filename, type: "image/jpeg")
  end
end
