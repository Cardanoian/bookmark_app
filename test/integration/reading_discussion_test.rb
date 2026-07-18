require "test_helper"

# 독서 토론(reading_discussion) e2e. 고아였던 토론 스택을 표면화하며 함께 출하한
# ① 도감 도달성(토론 글 → dex 03 해금) ② 기능 플래그 컨트롤러 강제(kill switch)
# ③ 교사 경계(classroom_id nil 교사도 Classroom.teacher_id 로 개설·모더레이션)
# ④ 아동 안전(금칙어·길이·신고·저자 학급 라우팅) ⑤ 진입점 노출을 검증한다.
class ReadingDiscussionTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "토론출하초")
    @class1 = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @class2 = Classroom.create!(school: @school, grade: 5, class_no: 2)
    # 교사는 운영과 동일하게 classroom_id nil — 담임 관계는 Classroom.teacher_id 로만 성립한다.
    @teacher = User.create!(school: @school, name: "토론담임", role: :teacher, email: "t1@example.com", password: "password")
    @class1.update!(teacher: @teacher)
    @other_teacher = User.create!(school: @school, name: "타반담임", role: :teacher, email: "t2@example.com", password: "password")
    @class2.update!(teacher: @other_teacher)
    @student1 = User.create!(school: @school, classroom: @class1, name: "토론학생1", password: "password")
    @student2 = User.create!(school: @school, classroom: @class1, name: "토론학생2", password: "password")
    @book = Book.create!(title: "토론책", author: "지은이", category: :recommended)
  end

  # ── ① 도감 도달성(핵심 버그 수정) ─────────────────────────────────
  test "posting a forum message discovers dex 03 (topic_posts) and announces it" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    login_as @student1

    assert_difference -> { @student1.user_monsters.where(dex_no: 3).count }, 1 do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "제 생각을 나눠요." } }
    end
    assert_includes flash[:notice], "새 몬스터"
  end

  # ── ② 기능 플래그 컨트롤러 강제(kill switch 실효) ─────────────────
  test "hard kill blocks forum post creation at the controller (not just the view)" do
    AppSetting.create!(key: "feature_flags", value: { "reading_discussion" => false })
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    login_as @student1

    assert_no_difference -> { ForumPost.count } do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "막혀야 함" } }
    end
    assert_redirected_to root_path
  end

  test "hard kill blocks the topics index too" do
    AppSetting.create!(key: "feature_flags", value: { "reading_discussion" => false })
    login_as @student1
    get topics_path
    assert_redirected_to root_path
  end

  # ── ③ 교사 경계(classroom_id nil 교사) ───────────────────────────
  test "teacher opens a classroom topic bound to their taught class (not nil)" do
    login_as @teacher
    assert_difference -> { Topic.count }, 1 do
      post topics_path, params: { topic: { title: "우리 반 책 토론", scope: "classroom", classroom_id: @class1.id } }
    end
    topic = Topic.last
    assert_equal @class1.id, topic.classroom_id, "교사 개설 토픽이 담당 학급에 묶여야 한다(고아 방지)"
    # 담당 학급 학생이 그 토픽을 볼 수 있어야 한다.
    login_as @student1
    get topic_path(topic)
    assert_response :success
  end

  test "teacher cannot open a topic for a class they do not teach" do
    login_as @teacher
    post topics_path, params: { topic: { title: "남의 반", scope: "classroom", classroom_id: @class2.id } }
    # 담당 학급이 아니라 classroom_id 로 확정 불가 → 모델 검증이 거부(고아 토픽 저장 안 됨).
    assert_not Topic.exists?(title: "남의 반")
  end

  test "teacher sees their taught class topics in policy scope" do
    class1_topic = Topic.create!(scope: :classroom, classroom: @class1, title: "1반 토론")
    class2_topic = Topic.create!(scope: :classroom, classroom: @class2, title: "2반 토론")
    scope = TopicPolicy::Scope.new(@teacher, Topic.all).resolve
    assert_includes scope, class1_topic
    assert_not_includes scope, class2_topic
  end

  # ── ③' 교사 모더레이션(저자 학급 경계) ───────────────────────────
  test "teacher hides a reported post by their own student, other-class teacher is forbidden" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    post = topic.forum_posts.create!(user: @student1, text: "신고 대상 글")
    ForumPostReport.create!(forum_post: post, user: @student2)

    login_as @other_teacher
    post teacher_forum_post_hide_path(post)
    assert_response :forbidden
    assert_not post.reload.hidden?

    login_as @teacher
    post teacher_forum_post_hide_path(post)
    assert post.reload.hidden?
    assert_equal @teacher.id, post.hidden_by_id
  end

  # ── ④ 아동 안전: 신고(저자 학급 라우팅·1인 1신고·자기 글 금지) ───
  test "a student reports another student's post and it surfaces to the author's teacher" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    post = topic.forum_posts.create!(user: @student2, text: "신고 받을 글")
    login_as @student1

    assert_difference -> { post.reload.reports_count }, 1 do
      post forum_post_report_path(post)
    end
    # 중복 신고는 카운트를 올리지 않는다(1인 1신고).
    assert_no_difference -> { post.reload.reports_count } do
      post forum_post_report_path(post)
    end

    # 저자(@student2)의 담임 대시보드에 신고 글이 뜬다(신고자 학급이 아니라 저자 학급 기준).
    login_as @teacher
    get teacher_dashboard_path
    assert_match "신고된 토론 글", response.body
  end

  test "a student cannot report their own post" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    post = topic.forum_posts.create!(user: @student1, text: "내 글")
    login_as @student1
    assert_no_difference -> { post.reload.reports_count } do
      post forum_post_report_path(post)
    end
    assert_response :forbidden
  end

  test "reporting does not auto-hide the post (anti-brigading)" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    post = topic.forum_posts.create!(user: @student2, text: "정상 글인데 신고당함")
    ForumPostReport.create!(forum_post: post, user: @student1)
    login_as @teacher # 세 번째 사용자 없이도 두 명이면 자동숨김되지 않아야 함
    ForumPostReport.create!(forum_post: post, user: @teacher)
    assert_not post.reload.hidden?, "또래 저작물은 신고 수만으로 자동 숨김되지 않는다(교사 검토만)"
  end

  # ── ④' 아동 안전: 금칙어(오탐 회귀)·길이 ─────────────────────────
  test "clear profanity is rejected on save" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    login_as @student1
    assert_no_difference -> { ForumPost.count } do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "이 글에는 씨발 이 들어감" } }
    end
    assert_redirected_to topic_path(topic)
  end

  test "normal words that merely contain an ambiguous substring are NOT blocked" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    login_as @student1
    # '곰 새끼'(동물 새끼)·'불이 꺼져'는 정상 표현 — FORUM 리스트에서 제외돼 저장돼야 한다.
    assert_difference -> { ForumPost.count }, 1 do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "곰 새끼가 정말 귀엽고, 불이 꺼져서 무서웠어요." } }
    end
  end

  test "too-short text is rejected" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    login_as @student1
    assert_no_difference -> { ForumPost.count } do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "짧" } }
    end
  end

  # ── ⑤ 진입점 노출 ────────────────────────────────────────────────
  test "reading activity page shows a book-anchored discussion entry point" do
    Topic.create!(scope: :classroom, classroom: @class1, title: "책토론", book: @book)
    login_as @student1
    get reading_activity_path(book_id: @book.id)
    assert_response :success
    assert_match "이 책으로 토론하기", response.body
    assert_match "책토론", response.body
  end

  test "topics views render the student nav so students do not feel stranded" do
    Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    login_as @student1
    get topics_path
    assert_match "학생 메뉴", response.body
  end
end
