# Resend API 키 배선(ActionMailer delivery_method `:resend` 가 사용).
#
# **lazy 프록으로 넘긴다.** 젬은 `Resend.api_key` 에 호출 가능 객체를 허용하며, 이 경우 실제
# 발송 시점에 평가한다. 부팅 시점에 credentials 를 강제로 읽지 않으므로:
#   · 키가 없는 개발·CI 환경에서도 부팅이 안전하고(무키 완전동작 원칙, docs/API_KEYS.md §0),
#   · 운영자가 키를 바꿔도 프로세스 재시작만으로 반영된다.
#
# 키 조회 자체의 단일 진실은 `Mail::ResendGateway` 다(ENV 우선 → credentials 폴백).
Resend.api_key = -> { Mail::ResendGateway.api_key }
