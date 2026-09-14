require "test_helper"
require "rake"

class DemoDataTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("demo_data:public_classroom_audit")
  end

  test "public_classroom_audit is a read-only dry run" do
    task = Rake::Task["demo_data:public_classroom_audit"]
    task.reenable

    output = capture_io { task.invoke }.first

    assert_includes output, "DRY RUN"
    assert_includes output, "target_found=false"
  end

  test "public_classroom_refresh refuses to run without the explicit production confirmation" do
    previous_demo = ENV["DEMO_DEPLOYMENT"]
    previous_confirm = ENV["CONFIRM"]
    ENV["DEMO_DEPLOYMENT"] = "1"
    ENV["CONFIRM"] = nil
    task = Rake::Task["demo_data:public_classroom_refresh"]
    task.reenable

    error = assert_raises(DemoData::PublicClassroomRefresh::SafetyError) { task.invoke }

    assert_includes error.message, "CONFIRM="
  ensure
    ENV["DEMO_DEPLOYMENT"] = previous_demo
    ENV["CONFIRM"] = previous_confirm
  end
end
