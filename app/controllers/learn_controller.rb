# 단계 학습 위저드 5단계(P5.5, RAILS_PLAN §13.3). 2022 개정 성취기준 코드를 단계마다 주입한다.
# 진행 상태는 세션에 저장되어 이탈 후 복귀 시 복원되며, 완료하면 5단계 답안을 모아
# 독후감 초안(reports#new 프리필)으로 연결한다.
class LearnController < ApplicationController
  # 5단계 정의(순서 고정). code = 성취기준, prompt = 학생 안내 질문.
  STEPS = [
    { code: "[6국02-05]", title: "책 고르기",
      prompt: "어떤 책을 읽었나요? 책 제목과 그 책을 고른 까닭을 적어 보세요." },
    { code: "[6국05-03]", title: "줄거리",
      prompt: "책의 줄거리를 사건 순서대로 간단히 정리해 보세요." },
    { code: "[6국05-04]", title: "인상 깊은 장면",
      prompt: "가장 인상 깊었던 장면과 그 까닭을 적어 보세요." },
    { code: "[6국03-03]", title: "내 생각·느낌",
      prompt: "그 장면에서 든 나의 생각과 느낌을 구체적으로 적어 보세요." },
    { code: "[6국05-06]", title: "삶과 연결",
      prompt: "이 책이 나의 삶·경험과 어떻게 연결되는지 적어 보세요." }
  ].freeze

  STEP_COUNT = STEPS.length

  def index
    authorize :learn, :index?

    @step = current_step
    @definition = STEPS[@step - 1]
    @answers = wizard_answers
    @answer = @answers[@step.to_s].to_s
  end

  # 현재 단계 답안을 저장하고 다음 단계로. 마지막 단계면 독후감 초안으로 완료.
  def advance
    authorize :learn, :advance?

    step = submitted_step
    store_answer(step, params[:answer].to_s)

    if step >= STEP_COUNT
      complete_wizard
    else
      wizard["step"] = step + 1
      redirect_to learn_index_path
    end
  end

  private

  def wizard
    session[:learn_wizard] ||= { "step" => 1, "answers" => {} }
  end

  def wizard_answers
    wizard["answers"] ||= {}
  end

  # 세션에 저장된 현재 단계(1..STEP_COUNT 범위로 보정).
  def current_step
    wizard["step"].to_i.clamp(1, STEP_COUNT)
  end

  def submitted_step
    params[:step].to_i.clamp(1, STEP_COUNT)
  end

  def store_answer(step, answer)
    wizard_answers[step.to_s] = answer
  end

  # 5단계 답안을 모아 독후감 초안으로 reports#new 를 프리필한다. 세션 진행은 소비(초기화).
  def complete_wizard
    answers = wizard_answers
    book_title = answers["1"].to_s.strip.lines.first.to_s.strip
    body = STEPS.each_with_index.map do |definition, index|
      "[#{definition[:title]}] #{answers[(index + 1).to_s]}"
    end.join("\n\n")

    session.delete(:learn_wizard)
    redirect_to new_report_path(report: { book_title: book_title, body: body }),
                notice: "단계 학습을 마쳤어요! 모아 둔 내용으로 독후감을 완성해 볼까요?"
  end
end
