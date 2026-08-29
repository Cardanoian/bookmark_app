require "test_helper"

# Hotwire Native 브리지 배선의 계약 테스트.
#
# 브리지는 **앱에서만** 동작하므로 웹 테스트로는 실제 저장·인쇄를 확인할 수 없다. 대신 여기서는
# 앱이 의존하는 **서버 쪽 조건**을 고정한다. 이 조건이 깨지면 배포된 APK 에서 버튼이 조용히
# 무반응이 되는데, 웹에서는 아무 증상도 보이지 않아 회귀를 눈치채기 어렵다.
class NativeBridgeTest < ActionDispatch::IntegrationTest
  # 앱의 `ChaekgalpiApplication.configureBridge()` 등록 이름과 **같아야 한다**.
  COMPONENTS = %w[save-image print].freeze

  setup do
    @school = School.create!(name: "브리지테스트학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @teacher = User.create!(
      school: @school, name: "브리지교사", email: "bridge-teacher@example.com",
      password: "password", role: :teacher
    )
    @classroom.update!(teacher: @teacher)
    @student = User.create!(
      school: @school, classroom: @classroom, name: "브리지학생", password: "password"
    )
  end

  test "브리지 라이브러리를 자체 호스팅으로 핀한다" do
    # 외부 CDN 을 쓰면 CSP 의 script-src :self 를 열어야 하고, 초등 대상 서비스의 네트워크
    # 표면이 넓어진다. 파일이 저장소 안에 있어야 오프라인 심사(Docker)에서도 동작한다.
    importmap = Rails.root.join("config", "importmap.rb").read
    assert_match(/pin "@hotwired\/hotwire-native-bridge"/, importmap)

    vendored = Rails.root.glob("vendor/javascript/*hotwire-native-bridge*.js")
    assert vendored.any?, "브리지 JS 가 vendor/javascript 에 없다(자체 호스팅이 아니다)"
  end

  test "브리지 컨트롤러의 component 이름이 앱 등록 이름과 같다" do
    # 이름이 계약이다. 한쪽만 바꾸면 앱에서 버튼이 무반응이 되고 화면에는 아무 표시도 없다.
    sources = {
      "save-image" => Rails.root.join("app/javascript/controllers/save_image_controller.js"),
      "print" => Rails.root.join("app/javascript/controllers/print_controller.js")
    }

    COMPONENTS.each do |component|
      path = sources.fetch(component)
      assert path.exist?, "#{component} 브리지 컨트롤러가 없다: #{path}"
      assert_match(/static component = "#{Regexp.escape(component)}"/, path.read,
                   "#{path.basename} 의 component 이름이 '#{component}' 가 아니다")
    end
  end

  test "인쇄 화면이 print 브리지와 웹 폴백을 함께 남긴다" do
    login_as @teacher
    get portfolio_teacher_prints_path(student_id: @student.id)
    assert_response :success

    # 앱: 브리지 컨트롤러가 붙는다.
    assert_select "button[data-controller~=print][data-action~='print#print']", 1

    # 웹: 인라인 폴백이 그대로 남아 있어야 한다. 이 속성이 사라지면 브라우저에서 인쇄가 죽는다
    # (CSP sha256 해시 대상이라 문구를 바꾸면 initializer 도 함께 바꿔야 한다).
    assert_select "button[onclick='window.print()']", 1
  end

  test "포트폴리오가 save-image 브리지와 웹 폴백을 함께 남긴다" do
    login_as @teacher
    get portfolio_teacher_prints_path(student_id: @student.id)
    assert_response :success

    assert_select "[data-controller~=save-image][data-save-image-filename-value]", 1
    assert_select "canvas[data-save-image-target=canvas][data-growth-card-target=canvas]", 1

    # 두 액션이 함께 걸려야 한다. 웹에서는 growth-card 만, 앱에서는 save-image 만 실제로 돈다.
    assert_select "button[data-action='growth-card#download save-image#save']", 1
  end

  test "저장 파일명에 학생 이름이 들어간다" do
    # 교사가 여러 학생 카드를 내려받을 때 파일명이 겹치지 않아야 한다.
    login_as @teacher
    get portfolio_teacher_prints_path(student_id: @student.id)

    assert_select "[data-save-image-filename-value]" do |elements|
      value = elements.first["data-save-image-filename-value"]
      assert_includes value, @student.name
      assert value.end_with?(".png"), "확장자가 있어야 기기에서 열린다: #{value}"
    end
  end
end
