require "test_helper"
require "rake"

class BooksDeduplicateTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("books:deduplicate_isbn")
    @task = Rake::Task["books:deduplicate_isbn"]
  end

  test "defaults to a read-only dry-run" do
    create_legacy_book!(title: "중복책", isbn: "979-11-5836-037-5", category: :recommended)
    duplicate = create_legacy_book!(title: "중복책", isbn: "9791158360375", category: :searched)

    output = run_task

    assert_includes output, "DRY RUN"
    assert_includes output, "Detected=1"
    assert Book.exists?(duplicate.id)
  end

  test "APPLY=1 merges detected duplicates" do
    canonical = create_legacy_book!(title: "중복책", isbn: "979-11-5836-037-5", category: :recommended)
    duplicate = create_legacy_book!(title: "중복책", isbn: "9791158360375", category: :searched)

    output = run_task(apply: "1")

    assert_includes output, "APPLY mode"
    assert_includes output, "merged=1"
    assert_not Book.exists?(duplicate.id)
    assert_equal "9791158360375", canonical.reload.isbn
  end

  private

  def run_task(apply: nil)
    previous = ENV["APPLY"]
    ENV["APPLY"] = apply
    @task.reenable
    capture_io { @task.invoke }.first
  ensure
    ENV["APPLY"] = previous
  end
end
