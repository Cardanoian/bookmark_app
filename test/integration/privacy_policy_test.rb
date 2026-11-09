require "test_helper"

class PrivacyPolicyPageTest < ActionDispatch::IntegrationTest
  # 처리방침은 가입 전 교사·보호자도 읽어야 하므로 로그인 없이 열린다.
  test "the privacy policy is public and starts at the policy title" do
    get privacy_policy_path

    assert_response :success
    assert_select "h1", text: "「책갈피」 개인정보 처리방침"
    assert_select "a[href='#{new_session_path}']", text: /로그인 화면으로/
    assert_includes response.body, "개인정보 처리방침을 수립·공개합니다"
    assert_select "h3#article-1", text: "제1조(개인정보의 처리 목적)"
    assert_select "h3#article-17", text: "제17조(개인정보 처리방침의 변경)"
    assert_select "h2#appendix-2", text: "부록 2. 어린이를 위한 개인정보 처리방침"
  end

  # 원본 첫머리 HTML 주석은 운영자 메모(미확정 쟁점·서버 주소·코드와 어긋나는 곳)라 공개하면 안 된다.
  test "the editor notes above the title never reach the page" do
    get privacy_policy_path

    [ "<!--", "편집 원본", "133.186.251.153", "운영자 판단이 필요한 쟁점", "코드와 방침이 아직 맞지 않는 곳" ].each do |note|
      assert_not_includes response.body, note
    end
  end

  test "tables, table of contents links and inline formatting render as HTML" do
    get privacy_policy_path

    assert_select "[data-role=privacy-policy] table th", text: "수탁자"
    assert_select "[data-role=privacy-policy] table td br" # 표 칸 안 <br> 줄바꿈
    assert_select "a[href='#article-7']", text: "제7조 개인정보의 국외 이전에 관한 사항"
    assert_select "a[href='#appendix-1']", text: "부록 1 생성형 AI 활용에 관한 안내"
    assert_select "strong", text: "책갈피가 아는 것"
    assert_select "ol[start='2'] li", text: /이용하는 AI/
    assert_select "[data-role=privacy-policy] ol > li > ul > li", text: /\A1\) 전자적 파일 형태의 정보/
    assert_not_includes response.body, "**"
  end

  # 원본의 [글자](https://…) 는 외부 링크로 — 웹은 새 탭, 앱(WebView 는 target=_blank 를 무시)은 target 없이.
  test "markdown links in the policy become external links" do
    get privacy_policy_path

    assert_select "[data-role=privacy-policy] a[href='https://resend.com/security'][target='_blank'][rel='noopener noreferrer']",
      text: "Resend의 보안 안내"
    assert_not_includes response.body, "](https://"

    get privacy_policy_path, headers: { "User-Agent" => "Mozilla/5.0 (Linux; Android 14) Hotwire Native Android; Turbo Native Android" }

    assert_select "[data-role=privacy-policy] a[href='https://resend.com/security']:not([target])", text: "Resend의 보안 안내"
  end

  # 닉네임을 아직 정하지 않은 학생도 설정 화면으로 끌려가지 않고 읽을 수 있다.
  test "a signed-in student who has not set a nickname can still read it" do
    school = School.create!(name: "처리방침초등학교")
    classroom = Classroom.create!(school: school, grade: 4, class_no: 2)
    student = User.create!(school: school, classroom: classroom, name: "처리방침학생", password: "password")
    login_as(student, onboarded: false)

    get privacy_policy_path

    assert_response :success
    assert_select "a[href='#{root_path}']", text: /홈으로/
  end
end
