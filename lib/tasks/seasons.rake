# 랭킹 시즌제 운영·관측 rake(account_linking_seasons_plan §Phase 5). 시드가 아니라 운영 태스크다.
#   seasons:reconcile — 현재 학년도 season_scores 합 불변식·유령행·중복·음수 점검(읽기 전용, 파괴 0).
namespace :seasons do
  desc "현재 학년도 season_scores 합 불변식·유령행·중복 점검 리포트(읽기 전용)"
  task reconcile: :environment do
    year = Classroom.current_academic_year

    puts "== 시즌 점검 (학년도 #{year}, #{Time.current.strftime('%Y-%m-%d %H:%M')}) =="

    current = SeasonScore.for_year(year)
    puts "현재 학년도 행: #{current.count}"
    puts "  experience_earned 합: #{current.sum(:experience_earned)}"
    puts "  points_earned 합: #{current.sum(:points_earned)}"

    puts "\n[학년도별 행 분포]"
    distribution = SeasonScore.group(:academic_year).order(:academic_year).count
    if distribution.any?
      distribution.each { |season_year, count| puts "  #{season_year}: #{count}행" }
    else
      puts "  (시즌 점수 없음)"
    end

    puts "\n[무결성]"
    # 유령 행: season_scores.user_id 가 users 에 없음(FK cascade 라 정상 0).
    ghost = SeasonScore.where.not(user_id: User.select(:id)).count
    puts "  유령 행(존재 안 하는 user_id): #{ghost}#{ghost.zero? ? ' ✓' : ' ⚠️'}"

    # 음수 점수(모델 검증이 막지만 raw 점검).
    negative = SeasonScore.where("experience_earned < 0 OR points_earned < 0").count
    puts "  음수 점수 행: #{negative}#{negative.zero? ? ' ✓' : ' ⚠️'}"

    # 중복 신원([academic_year, user_id] 유니크라 정상 0).
    duplicate_groups = SeasonScore.group(:academic_year, :user_id).having("COUNT(*) > 1").count.size
    puts "  중복 [academic_year, user_id]: #{duplicate_groups}#{duplicate_groups.zero? ? ' ✓' : ' ⚠️'}"

    # 비학생 소유 시즌 행(Pointable 훅은 학생·학급소속만 축적 — 정상 0 에 가까움, 참고 지표).
    non_student = SeasonScore.joins(:user).where.not(users: { role: User.roles[:student] }).count
    puts "  비학생 소유 시즌 행(참고): #{non_student}"
  end
end
