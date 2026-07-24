# 개발용 샘플 독서 퀴즈 시드(P5.6). 시드된 도서 1권에 대해 게시(published) 전역 퀴즈를
# 하나 만들어 quiz(mcq) 게임을 곧바로 플레이할 수 있게 한다. 멱등(find_or_initialize_by title).
namespace :quizzes do
  desc "Seed a sample published quiz for a seeded book"
  task seed: :environment do
    creator = User.find_by(role: :superadmin)
    book = Book.find_by(title: "마당을 나온 암탉") || Book.order(:id).first

    if creator.nil? || book.nil?
      puts "Skipped quizzes:seed (need a superadmin and at least one book)."
      next
    end

    title = "#{book.title} 독서 퀴즈"
    quiz = Quiz.find_or_initialize_by(title: title)
    quiz.book = book
    quiz.created_by = creator
    quiz.scope = :global
    quiz.published = true
    # Phase 1 콘텐츠축 메타(#9-seed): 교사/전역 출제 퀴즈이므로 origin=teacher, 콘텐츠축=mcq,
    # 학년군은 학급 없는 전역이라 g56 폴백, content_version=1. 시드가 Phase 1 컬럼과 함께
    # 깨끗이 재현되도록 명시한다(멱등: find_or_initialize 로 재실행에도 값 고정).
    quiz.origin = :teacher
    quiz.content_axis = :mcq
    quiz.band = ReadingDomain.band_for(quiz.classroom&.grade)
    quiz.content_version = 1
    quiz.save!

    if quiz.quiz_questions.none?
      Ai::QuizDraftService.new.call(book, count: 5).each_with_index do |question, index|
        quiz.quiz_questions.create!(
          prompt: question[:prompt],
          choices: question[:choices],
          answer_index: question[:answer_index],
          position: index + 1,
          question_type: :mcq_single,
          source: :manual
        )
      end
    end

    puts "Seeded sample quiz ##{quiz.id} (#{quiz.quiz_questions.count} questions) for '#{book.title}'."
  end
end
