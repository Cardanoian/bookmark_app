# 개인정보 처리방침 공개본 만들기(시드 아님).
#
#   privacy_policy:publish   — 편집 원본 docs/PRIVACY_POLICY.md → 공개본 config/privacy_policy.md
#
# 편집 원본은 운영자 메모(첫머리 HTML 주석)가 든 docs/ 중첩 저장소 파일이라 배포·CI 에 들어가지 않는다.
# 앱 화면(/privacy)은 공개본만 읽으므로, 편집 원본을 고친 뒤 이 태스크를 돌리고 공개본을 커밋·배포한다.
# 공개본은 제목 줄부터, HTML 주석을 지운 것이다(PrivacyPolicyDocument.public_text 와 같은 규칙).
namespace :privacy_policy do
  desc "편집 원본(docs/PRIVACY_POLICY.md)에서 공개본(config/privacy_policy.md)을 다시 만든다"
  task publish: :environment do
    source = PrivacyPolicyDocument::EDITOR_SOURCE_PATH
    abort "편집 원본이 없습니다: #{source}" unless File.exist?(source)

    text = PrivacyPolicyDocument.public_text(File.read(source))
    PrivacyPolicyDocument.parse(text) # 화면이 그릴 수 없는 공개본은 쓰지 않는다
    File.write(PrivacyPolicyDocument::SOURCE_PATH, text)
    puts "공개본을 썼습니다: #{PrivacyPolicyDocument::SOURCE_PATH.relative_path_from(Rails.root)} (#{text.lines.size}줄)"
  end
end
