module ApplicationHelper
  # 공통 학생 헤더의 뒤로가기 목적지. 외부 Referer와 인증 화면은 제외해
  # 앱 밖으로 나가거나 로그인 화면으로 되돌아가는 동작을 막는다.
  def student_back_path
    return root_path if request.referer.blank?

    referrer = URI.parse(request.referer)
    origin = URI.parse(request.base_url)
    same_origin = referrer.scheme == origin.scheme && referrer.host == origin.host && referrer.port == origin.port
    return root_path unless same_origin

    path = referrer.request_uri
    return root_path if path == request.fullpath || path.match?(%r{\A/(?:login|session)(?:/|\?|\z)})

    path
  rescue URI::InvalidURIError
    root_path
  end
end
