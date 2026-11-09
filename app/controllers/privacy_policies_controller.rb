# 개인정보 처리방침(공개 화면). 로그인 화면 3곳의 '개인정보 처리방침' 버튼(shared/_credits_footer)이
# 이리로 온다. 처리방침은 로그인하지 않은 사람(가입 전 교사·보호자)도 읽을 수 있어야 하므로
# 로그인·닉네임 설정 게이트를 타지 않고, 인가할 리소스가 없어 Pundit 검사도 건너뛴다.
class PrivacyPoliciesController < ApplicationController
  skip_before_action :require_login, only: [ :show ]
  skip_before_action :require_student_ranking_profile, only: [ :show ]
  skip_after_action :verify_authorized, only: [ :show ]

  def show
    @blocks = PrivacyPolicyDocument.blocks
  end
end
