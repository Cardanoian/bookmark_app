# 콘텐츠축 캐시 dedup 권위 = DB 부분 유니크 인덱스(Phase 2b §2b.4, A2).
#
# (book_id, band, content_axis, content_version) 조합이 origin=system 행에서 유일하도록 강제한다.
# thundering-herd(같은 축을 동시에 요청)에서도 `insert rescue RecordNotUnique`로 1생성만 남게 하는
# 근거 제약이다. 이 인덱스가 없으면 dedup 이 애플리케이션 레이어 경쟁 상태에 노출된다.
#
# ⚠️ 술어는 반드시 **정수 enum 값**이어야 한다(A2). origin 은 정수 컬럼이므로 문자열 술어
#    `WHERE origin = 'system'` 은 정수 컬럼과 0행 매칭 → dedup 이 조용히 무효화된다.
#    Quiz.origins[:system] == 1 을 정수로 박고, 아래 상수와 값이 일치함을 테스트로 고정한다.
#    teacher 행(origin=0)은 부분 술어에서 제외되어 자유롭게 중복될 수 있다(교사 퀴즈는 dedup 대상 아님).
class AddDedupUniqueIndexToQuizzes < ActiveRecord::Migration[8.1]
  # Quiz.origins[:system] 의 정수값. 부분 인덱스 술어에 문자열이 아니라 이 정수를 쓴다(A2).
  SYSTEM_ORIGIN = 1

  def change
    add_index :quizzes, [ :book_id, :band, :content_axis, :content_version ],
              unique: true,
              where: "origin = #{SYSTEM_ORIGIN}",
              name: "index_quizzes_on_content_axis_dedup"
  end
end
