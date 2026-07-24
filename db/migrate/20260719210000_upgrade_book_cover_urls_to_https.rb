class UpgradeBookCoverUrlsToHttps < ActiveRecord::Migration[8.1]
  # HTTPS 배포(force_ssl)에서 http:// 표지 URL 은 브라우저 혼합 콘텐츠 차단으로 표지가 안 뜬다.
  # 시드·검색으로 유입된 기존 http:// 표지(주로 알라딘, https 지원)를 https:// 로 일괄 승격한다.
  # 데이터 전용·멱등(선행 http:// 만 치환, 재실행 무해). 이후 신규 저장은 Book 모델의
  # before_validation :upgrade_cover_url_to_https 콜백이 같은 정규형을 유지한다.
  def up
    execute(<<~SQL)
      UPDATE books
      SET cover_url = 'https://' || substr(cover_url, 8)
      WHERE cover_url LIKE 'http://%'
    SQL
  end

  def down
    # http:// 로 되돌릴 실익이 없고(차단 상태 복원), 원본 스킴 구분도 소실됐으므로 비가역.
  end
end
