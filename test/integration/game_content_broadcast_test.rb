require "test_helper"

# 워밍 완료 방송(`GenerateGameContentJob#broadcast_ready`)이 **실제 화면에 닿는지** 고정한다.
#
# 이 방송은 오랫동안 짝이 없었다. 잡은 `[book_id, band, content_axis, :game_content]` 스트림에
# `target: "game_content_status"` 로 "새 문제가 준비됐어요!" 를 쏘는데, 코드베이스 어디에도 그
# 스트림을 구독하는 `turbo_stream_from` 도, 그 id 를 가진 요소도 없었다. 온디맨드 문제 생성이
# 끝나도 학생은 아무것도 못 보고, **크래시도 로그도 남지 않는다** — 눈으로는 절대 못 잡는 결함이다.
#
# 그래서 "구독이 있다" 로 끝내지 않고 **잡이 실제로 쏘는 것과 화면이 실제로 받는 것을 맞대어**
# 본다. 스트림 이름은 서명값끼리, 대상 id 는 방송 payload 에서 뽑아 화면에서 찾는다. 어느 한쪽만
# 이름·순서·타입이 바뀌어도 여기서 깨진다.
class GameContentBroadcastTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "방송초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1) # → band g56
    @student = User.create!(school: @school, classroom: @classroom, name: "방송학생", password: "password")
    @book = Book.create!(title: "방송책", author: "김저자",
                         summary: "모험을 떠난 소년의 긴 여정 이야기.", category: :recommended)
    CuratedQuiz.create!(book: @book, content_axis: :mcq, payload: [
      { "prompt" => "이야기의 주인공은 누구인가요?", "choices" => %w[소년 소녀 선생님 마법사], "answer_index" => 0, "explanation" => "소년이 모험을 떠나요.", "difficulty" => 1 },
      { "prompt" => "주인공은 무엇을 떠나나요?", "choices" => %w[모험 여행 학교 경기], "answer_index" => 0, "explanation" => "주인공은 모험을 떠나요.", "difficulty" => 1 },
      { "prompt" => "이야기에서 이어지는 것은 무엇인가요?", "choices" => %w[긴여정 짧은수업 요리시간 운동회], "answer_index" => 0, "explanation" => "긴 여정이 이어져요.", "difficulty" => 1 },
      { "prompt" => "주인공이 마주하는 것은 무엇인가요?", "choices" => %w[새로운경험 같은하루 빈교실 시험지], "answer_index" => 0, "explanation" => "모험 속에서 새로운 경험을 해요.", "difficulty" => 1 },
      { "prompt" => "이야기를 따라가며 알 수 있는 것은 무엇인가요?", "choices" => %w[여정의변화 정답지색깔 점심메뉴 책값], "answer_index" => 0, "explanation" => "주인공의 여정과 변화를 따라가요.", "difficulty" => 1 }
    ])
    login_as @student
  end

  test "온디맨드 퀴즈 화면이 잡과 같은 스트림을 구독한다" do
    get games_quiz_play_path(book_id: @book.id)
    assert_response :success

    quiz = on_demand_quiz
    # 3번째 인자는 assert_select 의 equality 라 Hash 로 count 를 주고 메시지는 4번째에 둔다
    # (String 을 그대로 넘기면 "텍스트 내용이 이것과 같은가" 로 해석된다).
    assert_select "turbo-cable-stream-source[signed-stream-name=?]",
                  Turbo::StreamsChannel.signed_stream_name(warming_stream(quiz)),
                  { count: 1 },
                  "잡이 쏘는 스트림과 화면이 거는 구독이 어긋나면 방송이 다시 짝을 잃는다"
  end

  test "워밍 완료 방송의 대상 id 가 그 화면에 실제로 존재한다" do
    get games_quiz_play_path(book_id: @book.id)
    assert_response :success
    quiz = on_demand_quiz

    streams = capture_turbo_stream_broadcasts(warming_stream(quiz)) do
      GenerateGameContentJob.new.send(:broadcast_ready, quiz)
    end

    assert_equal 1, streams.size
    assert_equal "append", streams.first["action"]
    # 방송이 지목한 자리를 **화면에서 직접 찾는다**. 잡의 target 이 바뀌거나 파셜에서 이 요소가
    # 사라지면 여기서 깨진다(둘 중 하나만 바뀌어도 조용히 죽는 것이 이 결함의 본질이었다).
    assert_select "##{streams.first["target"]}", 1
    assert_includes streams.first.to_html, "새 문제가 준비됐어요!"
  end

  test "교사가 발행한 퀴즈 화면에는 워밍 구독을 걸지 않는다" do
    # 워밍은 온디맨드(system) 판 전용이다. 교사 발행 퀴즈에까지 구독이 붙으면 학생이 볼 일 없는
    # 방송에 케이블 연결만 늘어난다.
    teacher = User.create!(school: @school, classroom: @classroom, name: "방송담임",
                           role: :teacher, password: "password")
    quiz = Quiz.create!(title: "선생님 퀴즈", created_by: teacher, book: @book, classroom: @classroom,
                        scope: :classroom, published: true, origin: :teacher,
                        content_axis: :mcq, band: :g56, generation_status: :ready)
    QuizQuestion.create!(quiz: quiz, prompt: "주인공은 누구인가요?", choices: %w[소년 소녀 선생님 마법사],
                         answer_index: 0, explanation: "소년이에요.", source: :curated, position: 1)

    get games_quiz_path(quiz)
    assert_response :success
    assert_select "#game_content_status", 0
  end

  private

  def on_demand_quiz
    Quiz.where(origin: :system, book_id: @book.id, content_axis: :mcq).order(:id).last.tap do |quiz|
      assert_not_nil quiz, "온디맨드 플레이가 system 퀴즈를 물질화해야 한다"
    end
  end

  # 잡이 쓰는 것과 **같은 순서·같은 타입**(AR 레코드에서 읽은 문자열)이어야 한다.
  def warming_stream(quiz)
    [ quiz.book_id, quiz.band, quiz.content_axis, :game_content ]
  end
end
