module ApplicationHelper
  # 학생 공통 헤더의 "뒤로가기" 목적지.
  #
  # 브라우저 히스토리 back(referer)이 아니라, 현재 요청의 컨트롤러/액션 기준으로
  # 한 단계 "상위 메뉴"를 계산한다. 예) reports#new → 독후감 목록(reports_path).
  # 최상위 7메뉴와 미등록 화면은 모두 내 서재(root_path)로 폴백한다.
  #
  # path helper 는 상수 값으로 저장할 수 없어(상수는 뷰 컨텍스트 밖에서 평가됨)
  # 심볼로 저장하고 렌더 시 public_send 로 호출한다.

  # "controller_path#action_name" → 상위가 곧 내 서재(root)인 화면들.
  #   최상위 7메뉴 + 네비 밖 최상위 목록(도서/학습/챌린지/게시판/토론/마이페이지).
  STUDENT_BACK_ROOT_SCREENS = %w[
    dashboard#show
    reports#index
    games/catalog#index
    monsters#index
    shops#show
    missions#index
    rankings#index
    books#index
    learn#index
    challenges#index
    board_posts#index
    topics#index
    profiles#show
  ].freeze

  # 자식 화면 → 상위 메뉴 경로(심볼). controller_path 단위 매핑.
  #   각 컨트롤러의 index 는 위 ROOT 목록이 root 로 가로채므로,
  #   여기 값은 show/new/edit 등 자식 액션에만 적용된다.
  STUDENT_BACK_PARENTS = {
    "reports"       => :reports_path,
    "monsters"      => :monsters_path,
    "missions"      => :missions_path,
    "books"         => :books_path,
    "challenges"    => :challenges_path,
    "board_posts"   => :board_posts_path,
    "topics"        => :topics_path,
    "passwords"     => :profile_path,       # 비밀번호 변경 → 마이페이지
    "games/quiz"    => :games_catalog_path,
    "games/classic" => :games_catalog_path,
    "games/vocab"   => :games_catalog_path,
    "games/whoami"  => :games_catalog_path,
    "games/book"    => :games_catalog_path
  }.freeze

  def student_back_path
    return root_path if STUDENT_BACK_ROOT_SCREENS.include?("#{controller_path}##{action_name}")

    public_send(STUDENT_BACK_PARENTS.fetch(controller_path, :root_path))
  end
end
