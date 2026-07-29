# 체험(데모) 계정 추가 콘텐츠 시드 — 담임 김지은의 학급 독서 퀴즈, 학생 이도현의 문제 기여
# (승인분은 전국 공유 풀로 물질화), 기존 승인 독후감 일부의 우수작 게시 + 응원.
# 데이터는 db/seeds/demo_content.yml, 로직은 db/seeds/demo_content_seeder.rb 가 단일 진실이며
# 무네트워크·멱등이다. db/seeds.rb 의 데모 게이트(SEED_DEMO=1 / DEMO_DEPLOYMENT=1)에서 호출되고,
# 이미 배포된 인스턴스에는 이 태스크만 따로 돌려 추가할 수 있다(bin/rails demo_content:seed).
namespace :demo_content do
  desc "Seed demo-account authored content (teacher quizzes, student contributions, featured reports)"
  task seed: :environment do
    require Rails.root.join("db/seeds/demo_content_seeder").to_s
    DemoContentSeeder.new.call
  end
end
