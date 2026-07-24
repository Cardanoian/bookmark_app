require "test_helper"

# 뒷이야기 격려 AI 코멘트 비동기 잡(AiReviewJob 미러, 가벼움). 무API에서도 규칙기반 폴백으로
# ai_status done + ai_comment 확보(네트워크 0·크래시 0)를 검증하고, 방송·삭제·실패 전이를 확인한다.
class SequelFeedbackJobTest < ActiveJob::TestCase
  setup do
    @school = School.create!(name: "코멘트잡학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @author = User.create!(school: @school, classroom: @classroom, name: "코멘트잡학생", password: "password")
    @book = Book.create!(title: "코멘트잡책", author: "지은이", category: :recommended)
    @sequel = BookSequel.create!(user: @author, book: @book, classroom: @classroom,
                                 body: "책이 끝난 뒤 주인공은 새 친구와 모험을 이어 갔어요.")
  end

  test "with no API key it still attaches an encouraging comment (fallback, done, no network)" do
    assert @sequel.pending?

    SequelFeedbackJob.perform_now(@sequel.id)

    @sequel.reload
    assert @sequel.done?
    assert @sequel.ai_comment.present?
  end

  test "uses the LLM comment when the service is stubbed as configured" do
    stub_new(Ai::SequelFeedbackService, FixedComment.new("상상력이 멋진 이야기예요!")) do
      SequelFeedbackJob.perform_now(@sequel.id)
    end

    assert_equal "상상력이 멋진 이야기예요!", @sequel.reload.ai_comment
    assert @sequel.done?
  end

  test "broadcasts the feedback replacement to the author's own sequel stream" do
    assert_turbo_stream_broadcasts(@sequel) do
      SequelFeedbackJob.perform_now(@sequel.id)
    end
  end

  test "marks the sequel failed when the service raises" do
    stub_new(Ai::SequelFeedbackService, RaisingService.new) do
      SequelFeedbackJob.perform_now(@sequel.id)
    end

    assert @sequel.reload.failed?
  end

  test "is a no-op when the sequel was deleted before the job ran" do
    id = @sequel.id
    @sequel.destroy!
    assert_nothing_raised { SequelFeedbackJob.perform_now(id) }
  end

  class FixedComment
    def initialize(comment) = (@comment = comment)
    def call(_sequel) = @comment
  end

  class RaisingService
    def call(_sequel) = raise("boom")
  end

  private

  # Minitest 6 dropped minitest/mock; temporarily swap `.new` on a service class.
  def stub_new(klass, replacement)
    klass.define_singleton_method(:new) { |*, **| replacement }
    yield
  ensure
    klass.singleton_class.send(:remove_method, :new)
  end
end
