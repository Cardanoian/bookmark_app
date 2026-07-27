# 초기 챌린지 시드(db/seeds/challenges.yml). 멱등: (scope, school_id, title) 을 신원으로
# find_or_initialize_by 하고 목표는 goal_type 당 1개를 upsert 한다(유니크 [challenge_id, goal_type]).
#
# 참여·보상 행(challenge_participations)은 만들지 않는다 — 챌린지는 전국/학교 스코프라 전원 배정이
# 비현실적이어서, 학생이 '참여하기'를 누를 때(ChallengesController#join) 참여 행이 생기고 그
# 시점(joined_at) 이후의 활동만 진행에 집계된다.
namespace :challenges do
  desc "Seed initial global/school challenges from db/seeds/challenges.yml"
  task seed: :environment do
    path = Rails.root.join("db/seeds/challenges.yml")
    unless File.exist?(path)
      puts "Challenge seed YAML unavailable (#{path}) — skipping."
      next
    end

    data = YAML.safe_load_file(path, aliases: false)
    raise "Challenge seed data must be a mapping: #{path}" unless data.is_a?(Hash)

    Array(data["challenges"]).each do |cd|
      scope = cd.fetch("scope")
      title = cd.fetch("title")

      school = nil
      if scope == "school"
        neis_code = cd.fetch("school_neis_code").to_s
        school = School.find_by(neis_code: neis_code)
        unless school
          puts "  Challenge '#{title}': 학교(neis=#{neis_code}) 없음 — 건너뜀."
          next
        end
      end

      challenge = Challenge.find_or_initialize_by(scope: scope, school_id: school&.id, title: title)
      created = challenge.new_record?
      challenge.assign_attributes(
        description: cd["description"],
        starts_on: cd["starts_on"],
        ends_on: cd["ends_on"],
        reward_points: cd.fetch("reward_points", 0).to_i
      )
      challenge.save!

      Array(cd["goals"]).each_with_index do |gd, index|
        goal = challenge.challenge_goals.find_or_initialize_by(goal_type: gd.fetch("type"))
        goal.target_count = gd.fetch("target").to_i
        goal.position = index
        goal.save!
      end

      label = school ? "#{school.name} 학교 챌린지" : "전국 챌린지"
      goals = challenge.challenge_goals.order(:position, :id)
                       .map { |g| "#{g.goal_type}=#{g.target_count}" }.join(" + ")
      puts "  #{created ? 'Created' : 'Synced'} #{label}: #{title} (#{goals}, #{challenge.reward_points}P)"
    end

    puts "Seeded challenges. Challenge.count = #{Challenge.count}"
  end
end
