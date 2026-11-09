# 개인정보 처리방침 공개본(config/privacy_policy.md)을 production 부팅 때 한 번 읽어 둔다.
# 공개본이 없거나 깨졌으면 여기서 부팅이 실패한다 — Docker 이미지 빌드의 assets:precompile 단계에서 멈추므로,
# /up 헬스체크는 통과했는데 로그인 화면의 '개인정보 처리방침' 버튼만 500 인 배포가 나가지 않는다.
Rails.application.config.after_initialize do
  PrivacyPolicyDocument.blocks if Rails.env.production?
end
