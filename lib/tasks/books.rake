# 도서 카탈로그 시드(P5.2). 초등 5~6학년 권장도서 + 고전을 적재한다.
#
# 프로토타입의 정확한 44권 목록은 이 저장소에 없어(RAILS_PLAN §13.3), 널리 알려진
# 초등 고학년 추천도서·고전으로 큐레이션한 대표 카탈로그를 사용한다.
# 멱등: title+author 로 find_or_initialize_by.
namespace :books do
  desc "Seed the representative book catalog (recommended + classic)"
  task seed: :environment do
    recommended = [
      { title: "마당을 나온 암탉", author: "황선미", publisher: "사계절", summary: "자유를 꿈꾸는 암탉 잎싹의 감동적인 성장 이야기." },
      { title: "몽실 언니", author: "권정생", publisher: "창비", summary: "전쟁과 가난 속에서도 동생들을 지켜 낸 몽실이의 이야기." },
      { title: "강아지똥", author: "권정생", publisher: "길벗어린이", summary: "쓸모없어 보이던 강아지똥이 민들레를 피우는 이야기." },
      { title: "초정리 편지", author: "배유안", publisher: "창비", summary: "훈민정음을 배우며 성장하는 장이의 이야기." },
      { title: "문제아", author: "박기범", publisher: "창비", summary: "어린이의 시선으로 세상을 바라본 단편 모음." },
      { title: "나쁜 어린이표", author: "황선미", publisher: "웅진주니어", summary: "상과 벌을 둘러싼 건우의 마음을 그린 이야기." },
      { title: "괭이부리말 아이들", author: "김중미", publisher: "창비", summary: "가난한 동네 아이들의 우정과 희망을 그린 이야기." },
      { title: "만복이네 떡집", author: "김리리", publisher: "비룡소", summary: "말버릇을 고쳐 주는 신기한 떡집 이야기." },
      { title: "푸른 사자 와니니", author: "이현", publisher: "창비", summary: "초원에서 살아남는 어린 사자 와니니의 모험." },
      { title: "해리엇", author: "한윤섭", publisher: "문학동네", summary: "거북이 해리엇의 눈으로 본 생명과 자유." },
      { title: "봉주르, 뚜르", author: "한윤섭", publisher: "문학동네", summary: "프랑스 작은 마을에서 펼쳐지는 우정과 비밀." },
      { title: "우리들의 일그러진 영웅", author: "이문열", publisher: "다림", summary: "교실 권력을 통해 사회를 비추는 성장 소설." },
      { title: "화요일의 두꺼비", author: "러셀 에릭슨", publisher: "사계절", summary: "두꺼비와 올빼미의 뜻밖의 우정 이야기." },
      { title: "마틸다", author: "로알드 달", publisher: "시공주니어", summary: "책을 사랑하는 특별한 소녀 마틸다의 이야기." },
      { title: "찰리와 초콜릿 공장", author: "로알드 달", publisher: "시공주니어", summary: "황금 티켓으로 초콜릿 공장을 방문한 찰리의 모험." },
      { title: "샬롯의 거미줄", author: "엘윈 브룩스 화이트", publisher: "시공주니어", summary: "돼지 윌버와 거미 샬롯의 따뜻한 우정." },
      { title: "기억 전달자", author: "로이스 로리", publisher: "비룡소", summary: "완벽해 보이는 사회의 비밀을 알게 된 소년의 이야기." },
      { title: "마법의 설탕 두 조각", author: "미하엘 엔데", publisher: "소년한길", summary: "부모를 마음대로 하려던 소녀가 배우는 교훈." },
      { title: "사자와 마녀와 옷장", author: "C. S. 루이스", publisher: "시공주니어", summary: "옷장 너머 나니아에서 펼쳐지는 모험." },
      { title: "젓가락 달인", author: "유타루", publisher: "바람의아이들", summary: "젓가락질을 배우며 자라는 아이의 이야기." },
      { title: "5월 35일", author: "에리히 캐스트너", publisher: "시공주니어", summary: "달력에 없는 날 떠나는 유쾌한 상상 여행." },
      { title: "클로디아의 비밀", author: "E. L. 코닉스버그", publisher: "비룡소", summary: "박물관에서 살기로 한 남매의 비밀 모험." },
      { title: "프린들 주세요", author: "앤드루 클레먼츠", publisher: "사계절", summary: "새로운 낱말을 만들어 낸 소년의 이야기." },
      { title: "안녕, 우주", author: "에린 엔트라다 켈리", publisher: "밝은미래", summary: "수줍은 아이들이 우주를 향해 마음을 여는 이야기." }
    ]

    classics = [
      { title: "어린 왕자", author: "앙투안 드 생텍쥐페리", publisher: "열린책들", summary: "사막에서 만난 어린 왕자와의 이야기." },
      { title: "오즈의 마법사", author: "라이먼 프랭크 바움", publisher: "비룡소", summary: "회오리바람에 실려 오즈로 간 도로시의 모험." },
      { title: "이상한 나라의 앨리스", author: "루이스 캐럴", publisher: "비룡소", summary: "토끼 굴로 떨어져 만난 이상한 나라 이야기." },
      { title: "톰 소여의 모험", author: "마크 트웨인", publisher: "시공주니어", summary: "장난꾸러기 톰의 강가 모험 이야기." },
      { title: "소공녀", author: "프랜시스 호지슨 버넷", publisher: "시공주니어", summary: "역경 속에서도 품위를 잃지 않은 세라의 이야기." },
      { title: "비밀의 화원", author: "프랜시스 호지슨 버넷", publisher: "시공주니어", summary: "버려진 정원을 되살리며 자라는 아이들의 이야기." },
      { title: "키다리 아저씨", author: "진 웹스터", publisher: "인디고", summary: "얼굴 모를 후원자에게 편지를 쓰는 주디의 이야기." },
      { title: "작은 아씨들", author: "루이자 메이 올콧", publisher: "펭귄클래식코리아", summary: "네 자매의 사랑과 성장을 그린 고전." },
      { title: "15소년 표류기", author: "쥘 베른", publisher: "비룡소", summary: "무인도에 표류한 소년들의 생존 모험." },
      { title: "홍길동전", author: "허균", publisher: "창비", summary: "차별에 맞서 활빈당을 이끈 홍길동 이야기." }
    ]

    upsert = lambda do |attrs, category|
      book = Book.find_or_initialize_by(title: attrs[:title], author: attrs[:author])
      book.publisher = attrs[:publisher]
      book.summary = attrs[:summary]
      book.grade_band = "초등 5~6"
      book.category = category
      book.save!
    end

    recommended.each { |attrs| upsert.call(attrs, :recommended) }
    classics.each { |attrs| upsert.call(attrs, :classic) }

    puts "Seeded books. recommended=#{Book.recommended.count} classic=#{Book.classic.count} total=#{Book.count}"
  end
end
