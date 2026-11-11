# 손글씨 사진을 JPEG 로 다시 써서 촬영 기기가 기록한 정보(EXIF·XMP·IPTC — 촬영 일시·기기·위치)를 지운다.
#
# 두 곳이 쓴다.
#   - 올릴 때(OcrController): **저장하기 전에** 지운 사본만 남긴다(`call`, 2026-11-11). 예전에는 브라우저
#     압축(photo_upload_controller.js)이 다시 쓰는 김에 정보가 빠지기를 기대했는데, 압축한 파일이 원본보다
#     크거나 브라우저가 사진을 열지 못하면 원본이 그대로 저장됐다.
#   - AI 로 보낼 때(Ai::OcrService): 이 정리 전에 올라온 사진도 있으니 보내기 직전에 한 번 더 지운다
#     (`encode_jpeg`·`leftover_metadata` 를 함께 쓴다).
#
# 지우지 못하면 Failed 다 — 원본으로 이어 가지 않는다. libvips 가 없는 호스트에서는 ruby-vips 로딩이
# `LoadError`(StandardError 가 아니다)를 던지므로 그것도 실패로 본다.
class PhotoSanitizer
  class Failed < StandardError; end
  # 크기(바이트·화소) 한도를 넘었다 — 다시 찍으면 되는 실패와 안내를 나눈다.
  class TooLarge < Failed; end

  METADATA_FIELDS = %w[exif-data xmp-data iptc-data].freeze
  # 휴대폰·태블릿 카메라가 내는 형식만 푼다. 저장 검증(Report#validate_attachment)은 이제 다시 쓴 JPEG 만 보므로,
  # 여기서 막지 않으면 libvips 가 읽을 수 있는 모든 것(PDF·SVG 등 — poppler·librsvg 가 요청 안에서 학생이 올린
  # 파일을 연다)이 사진으로 바뀌어 저장된다. 판별은 매직바이트 우선(Marcel)이라 이름만 바꾼 파일은 걸린다.
  ALLOWED_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/avif].freeze
  # 바이트 한도만으로는 부족하다 — 10MB 안에 수억 화소를 넣은 PNG 를 요청 안에서 풀면 수십 초가 걸린다.
  # 1억 800만 화소 카메라 원본까지는 받는다.
  MAX_PIXELS = 120_000_000
  # 담임 확대(ReportPhotosController::ZOOM_LIMIT 1600)·판독(Ai::OcrService::MAX_EDGE 1568)보다 크게 둬
  # 보이는 사진은 그대로다. 브라우저 압축을 거치지 않은 원본(수천만 화소, HEIC)을 같은 크기의 JPEG 로 다시
  # 쓰면 오히려 커져 Report::IMAGE_MAX_BYTES 를 넘을 수 있어서 줄인다.
  MAX_EDGE = 2048
  QUALITY = 90
  # 파일 이름도 바꾼다 — 휴대폰은 촬영 일시를 이름에 넣는다(IMG_20261111_093000.jpg).
  FILENAME = "photo.jpg".freeze

  # upload: 요청으로 들어온 파일(ActionDispatch::Http::UploadedFile). 반환: `attach` 에 그대로 넘길 Hash.
  def self.call(upload) = new.call(upload)

  # 긴 변을 max_edge 로 줄이고 메타데이터를 지운 JPEG 바이트. 방향(EXIF Orientation)은 지우기 전에 바로잡힌다 —
  # 첫 연산이 축소라 image_processing 이 vips_thumbnail 로 불러오고, thumbnail 이 기본으로 돌려 세운다. 그러지
  # 않으면 옆으로 누운 사진이 남는다. 투명한 부분은 흰 바탕으로 채운다(JPEG 에는 투명이 없어 그냥 쓰면 검은
  # 바탕이 돼, 투명 배경에 검은 글씨인 스캔·화면 캡처는 글씨가 사라진다).
  def self.encode_jpeg(file, max_edge:, quality:)
    resized = ImageProcessing::Vips.source(file)
      .resize_to_limit(max_edge, max_edge)
      .convert("jpg")
      .saver(quality: quality, strip: true, background: 255)
      .call
    File.binread(resized.path)
  ensure
    resized&.close!
  end

  # 다시 쓴 결과에 남은 메타데이터 필드(비어 있어야 한다). image_processing 은 saver 가 모르는 옵션을 예외
  # 없이 버리고 `strip` 은 libvips 8.15 부터 deprecated 라, 언젠가 옵션이 조용히 무시되면 정보가 붙은 사진이
  # 실패 없이 지나간다. 그래서 결과를 다시 읽어 본다(운영과 같은 libvips 8.16.1 에서 `strip: true` 가 EXIF 를
  # 지우는 것은 2026-11-09 실측).
  def self.leftover_metadata(bytes)
    METADATA_FIELDS & ::Vips::Image.new_from_buffer(bytes, "").get_fields
  end

  def initialize(max_pixels: MAX_PIXELS)
    @max_pixels = max_pixels
  end

  def call(upload)
    # 문자열(direct upload 로 미리 올린 blob 의 signed id 등)은 이미 저장된 원본이라 지울 수 없다.
    raise Failed, "not an uploaded file (#{upload.class})" unless upload.is_a?(ActionDispatch::Http::UploadedFile)
    # 풀기 전에 크기부터 본다 — 저장 검증(Report#validate_attachment)과 같은 한도.
    raise TooLarge, "photo is larger than #{Report::IMAGE_MAX_BYTES} bytes" if upload.size > Report::IMAGE_MAX_BYTES

    type = detected_type(upload)
    raise Failed, "not a camera photo format (#{type})" unless ALLOWED_TYPES.include?(type)

    { io: StringIO.new(jpeg(upload.tempfile)), filename: FILENAME, content_type: "image/jpeg" }
  end

  private

  def detected_type(upload)
    Marcel::MimeType.for(upload.tempfile, name: upload.original_filename)
  ensure
    upload.tempfile.rewind
  end

  def jpeg(file)
    ensure_pixels_within_limit!(file)
    bytes = encode(file)
    leftover = self.class.leftover_metadata(bytes)
    raise Failed, "metadata survived re-encoding (#{leftover.join(', ')})" if leftover.any?

    bytes
  rescue Failed
    raise
  rescue StandardError, LoadError => e
    raise Failed, "photo could not be re-encoded (#{e.class})"
  end

  # 머리(가로·세로)만 읽는다 — new_from_file 은 화소를 풀지 않는다.
  def ensure_pixels_within_limit!(file)
    require "vips"
    header = ::Vips::Image.new_from_file(file.path)
    pixels = header.width * header.height
    raise TooLarge, "photo has #{pixels} pixels (limit #{@max_pixels})" if pixels > @max_pixels
  end

  def encode(file) = self.class.encode_jpeg(file, max_edge: MAX_EDGE, quality: QUALITY)
end
