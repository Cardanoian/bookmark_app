require "test_helper"

class OcrJobTest < ActiveJob::TestCase
  setup do
    @school = School.create!(name: "OCR잡학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "OCR잡학생", password: "password")
    @report = Report.create!(user: @user, classroom: @classroom, book_title: "책", input_mode: :ocr)
    @report.photo.attach(io: StringIO.new("fake-image-bytes"), filename: "hw.png", content_type: "image/png")
  end

  class OcrStub
    def initialize(text)
      @text = text
    end

    def call(_blob)
      @text
    end
  end

  test "marks the report failed when OCR is unavailable (blank key, no network)" do
    OcrJob.perform_now(@report)
    assert @report.reload.failed?
  end

  test "sets the body and marks done when OCR succeeds (stubbed)" do
    stub_new(Ai::OcrService, OcrStub.new("인식된 손글씨 본문")) do
      OcrJob.perform_now(@report)
    end

    @report.reload
    assert_equal "인식된 손글씨 본문", @report.body
    assert @report.done?
  end

  private

  # Minitest 6 dropped minitest/mock; temporarily swap `.new` on a service class
  # to return an injected double, then restore the inherited Class#new.
  def stub_new(klass, replacement)
    klass.define_singleton_method(:new) { |*, **| replacement }
    yield
  ensure
    klass.singleton_class.send(:remove_method, :new)
  end
end
