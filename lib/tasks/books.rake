# 도서 카탈로그 시드(P5.2 → 계획 §3). 초등 전학년을 학년밴드별로 큐레이션한다.
#
# 소스: 학교도서관저널 추천도서목록 등 널리 알려진 초등 권장도서를 학년밴드(초등 1~2/3~4/5~6)로
# 큐레이션한 대표 카탈로그. grade_band 는 Book::GRADE_BANDS 표준 라벨로 고정한다(표시·필터 전용,
# 게임 밴드와 무관 — 계획 §3.1). 표지·ISBN 등 메타는 books:enrich(네이버) 로 사후 보강한다.
# 멱등: title+author 로 find_or_initialize_by.
#
# 오너가 학교도서관저널 전체 목록을 확정하면 아래 배열을 확장한다(현재는 확신 가능한 대표 큐레이션).
namespace :books do
  desc "Seed the graded book catalog (초등 1~2 / 3~4 / 5~6 + classics)"
  task seed: :environment do
    band_low, band_mid, band_high = Book::GRADE_BANDS

    # 초등 1~2 (저학년) — 그림책·짧은 이야기.
    low = [
      { title: "강아지똥", author: "권정생", publisher: "길벗어린이", summary: "쓸모없어 보이던 강아지똥이 민들레를 피우는 이야기." },
      { title: "구름빵", author: "백희나", publisher: "한솔수북", summary: "구름으로 만든 빵을 먹고 하늘을 나는 남매의 이야기." },
      { title: "알사탕", author: "백희나", publisher: "책읽는곰", summary: "마음의 소리를 들려주는 신기한 알사탕 이야기." },
      { title: "지각대장 존", author: "존 버닝햄", publisher: "비룡소", summary: "학교 가는 길마다 벌어지는 존의 유쾌한 상상." },
      { title: "무지개 물고기", author: "마르쿠스 피스터", publisher: "시공주니어", summary: "반짝이는 비늘을 나누며 참된 우정을 배우는 물고기." },
      { title: "프레드릭", author: "레오 리오니", publisher: "시공주니어", summary: "겨울을 위해 햇살과 색을 모으는 들쥐 프레드릭." },
      { title: "개구리와 두꺼비는 친구", author: "아놀드 로벨", publisher: "비룡소", summary: "두 친구가 나누는 따뜻한 일상 이야기 모음." },
      { title: "종이 봉지 공주", author: "로버트 먼치", publisher: "비룡소", summary: "용을 물리치고 스스로를 지킨 씩씩한 공주 이야기." },
      { title: "언제까지나 너를 사랑해", author: "로버트 먼치", publisher: "북뱅크", summary: "세대를 이어 전해지는 변함없는 사랑 이야기." },
      { title: "사과가 쿵!", author: "다다 히로시", publisher: "보림", summary: "커다란 사과를 나눠 먹는 동물들의 즐거운 이야기." },
      { title: "100층짜리 집", author: "이와이 도시오", publisher: "북뱅크", summary: "층마다 다른 친구가 사는 100층 집을 오르는 모험." },
      { title: "배고픈 애벌레", author: "에릭 칼", publisher: "더큰컴퍼니", summary: "먹고 자라 나비가 되는 애벌레의 한살이." },
      { title: "검피 아저씨의 뱃놀이", author: "존 버닝햄", publisher: "시공주니어", summary: "동물들과 함께 배를 타는 검피 아저씨의 하루." },
      { title: "손 큰 할머니의 만두 만들기", author: "채인선", publisher: "재미마주", summary: "동물들과 커다란 만두를 빚는 손 큰 할머니." },
      { title: "세상에서 가장 힘이 센 수탉", author: "이호백", publisher: "재미마주", summary: "가장 힘센 수탉이 나이 들며 배우는 삶의 의미." },
      { title: "아씨방 일곱 동무", author: "이영경", publisher: "비룡소", summary: "바느질 도구 일곱이 서로의 공을 다투는 옛이야기." },
      { title: "팥죽 할멈과 호랑이", author: "조대인", publisher: "보림", summary: "호랑이를 물리치는 팥죽 할멈과 물건들의 지혜." },
      { title: "돼지책", author: "앤서니 브라운", publisher: "웅진주니어", summary: "집안일을 돌아보게 하는 가족 이야기." },
      { title: "겁쟁이 빌리", author: "앤서니 브라운", publisher: "비룡소", summary: "걱정 인형과 함께 두려움을 이겨 내는 빌리." },
      { title: "당나귀 실베스터와 요술 조약돌", author: "윌리엄 스타이그", publisher: "다산기획", summary: "소원을 이뤄 주는 조약돌을 둘러싼 가족의 사랑." },
      { title: "치과 의사 드소토 선생님", author: "윌리엄 스타이그", publisher: "비룡소", summary: "여우 환자를 슬기롭게 대하는 생쥐 의사 이야기." },
      { title: "괴물들이 사는 나라", author: "모리스 샌닥", publisher: "시공주니어", summary: "상상 속 괴물 나라로 떠난 맥스의 하룻밤." },
      { title: "곰 사냥을 떠나자", author: "마이클 로젠", publisher: "시공주니어", summary: "가족이 함께 곰을 찾아 떠나는 리듬감 있는 모험." },
      { title: "백만 마리 고양이", author: "완다 가그", publisher: "시공주니어", summary: "가장 예쁜 고양이를 찾는 할아버지의 이야기." },
      { title: "으뜸 헤엄이", author: "레오 리오니", publisher: "마루벌", summary: "작은 물고기들이 힘을 모아 큰 물고기가 되는 이야기." },
      { title: "솔이의 추석 이야기", author: "이억배", publisher: "길벗어린이", summary: "온 가족이 모이는 정겨운 추석 풍경." },
      { title: "만희네 집", author: "권윤덕", publisher: "길벗어린이", summary: "정겨운 한옥과 마당을 그린 우리 집 이야기." },
      { title: "훨훨 간다", author: "권정생", publisher: "국민서관", summary: "할머니가 들려주는 이야기로 도둑을 쫓는 옛이야기." },
      { title: "오소리네 집 꽃밭", author: "권정생", publisher: "길벗어린이", summary: "있는 그대로의 자연이 아름다운 꽃밭임을 배우는 오소리." },
      { title: "넉 점 반", author: "윤석중", publisher: "창비", summary: "심부름 가는 아이의 느릿한 하루를 담은 동시 그림책." },
      { title: "안 돼, 데이빗!", author: "데이빗 섀넌", publisher: "지경사", summary: "장난꾸러기 데이빗과 엄마의 사랑을 그린 이야기." },
      { title: "도깨비를 빨아 버린 우리 엄마", author: "사토 와키코", publisher: "한림출판사", summary: "무엇이든 빨아 버리는 씩씩한 엄마와 도깨비." },
      { title: "엄마 마중", author: "이태준", publisher: "소년한길", summary: "전차 정거장에서 엄마를 기다리는 아이의 마음." },
      { title: "방귀쟁이 며느리", author: "신세정", publisher: "사계절", summary: "참았던 방귀로 한바탕 소동을 벌이는 옛이야기." }
    ]

    # 초등 3~4 (중학년) — 짧은 동화·생활 이야기.
    mid = [
      { title: "만복이네 떡집", author: "김리리", publisher: "비룡소", summary: "말버릇을 고쳐 주는 신기한 떡집 이야기." },
      { title: "화요일의 두꺼비", author: "러셀 에릭슨", publisher: "사계절", summary: "두꺼비와 올빼미의 뜻밖의 우정 이야기." },
      { title: "나쁜 어린이표", author: "황선미", publisher: "웅진주니어", summary: "상과 벌을 둘러싼 건우의 마음을 그린 이야기." },
      { title: "젓가락 달인", author: "유타루", publisher: "바람의아이들", summary: "젓가락질을 배우며 자라는 아이의 이야기." },
      { title: "마법의 설탕 두 조각", author: "미하엘 엔데", publisher: "소년한길", summary: "부모를 마음대로 하려던 소녀가 배우는 교훈." },
      { title: "프린들 주세요", author: "앤드루 클레먼츠", publisher: "사계절", summary: "새로운 낱말을 만들어 낸 소년의 이야기." },
      { title: "짜장 짬뽕 탕수육", author: "김영주", publisher: "재미마주", summary: "전학 온 아이가 친구를 사귀며 겪는 교실 이야기." },
      { title: "잘못 뽑은 반장", author: "이은재", publisher: "주니어김영사", summary: "얼떨결에 반장이 된 개구쟁이 로운이의 성장기." },
      { title: "내 짝꿍 최영대", author: "채인선", publisher: "재미마주", summary: "놀림받던 친구를 이해하게 되는 교실 이야기." },
      { title: "겁보 만보", author: "김유", publisher: "책읽는곰", summary: "겁 많은 만보가 용기를 찾아가는 이야기." },
      { title: "마틸다", author: "로알드 달", publisher: "시공주니어", summary: "책을 사랑하는 특별한 소녀 마틸다의 이야기." },
      { title: "찰리와 초콜릿 공장", author: "로알드 달", publisher: "시공주니어", summary: "황금 티켓으로 초콜릿 공장을 방문한 찰리의 모험." },
      { title: "샬롯의 거미줄", author: "엘윈 브룩스 화이트", publisher: "시공주니어", summary: "돼지 윌버와 거미 샬롯의 따뜻한 우정." },
      { title: "멋진 여우 씨", author: "로알드 달", publisher: "논장", summary: "농부들을 골탕 먹이는 꾀 많은 여우 씨." },
      { title: "조지, 마법의 약을 만들다", author: "로알드 달", publisher: "시공주니어", summary: "심술궂은 할머니에게 줄 약을 만드는 조지." },
      { title: "만년 샤쓰", author: "방정환", publisher: "길벗어린이", summary: "가난 속에서도 밝음을 잃지 않는 창남이 이야기." },
      { title: "5월 35일", author: "에리히 캐스트너", publisher: "시공주니어", summary: "달력에 없는 날 떠나는 유쾌한 상상 여행." },
      { title: "시간 가게", author: "이나영", publisher: "문학동네", summary: "행복을 값으로 치르고 시간을 사는 소녀의 이야기." },
      { title: "클로디아의 비밀", author: "E. L. 코닉스버그", publisher: "비룡소", summary: "박물관에서 살기로 한 남매의 비밀 모험." },
      { title: "안녕, 우주", author: "에린 엔트라다 켈리", publisher: "밝은미래", summary: "수줍은 아이들이 우주를 향해 마음을 여는 이야기." },
      { title: "우주 호텔", author: "유순희", publisher: "해와나무", summary: "폐지 줍는 종이 할머니가 되찾는 삶의 온기." },
      { title: "몬스터 차일드", author: "이재문", publisher: "사계절", summary: "병을 가진 남매가 편견에 맞서는 성장 이야기." },
      { title: "일기 감추는 날", author: "황선미", publisher: "웅진주니어", summary: "일기장을 둘러싼 아이와 엄마의 마음." },
      { title: "나의 산에서", author: "진 크레이그헤드 조지", publisher: "비룡소", summary: "산속에서 홀로 살아가는 소년의 자연 생존기." },
      { title: "스무고개 탐정과 마술사", author: "허교범", publisher: "시공주니어", summary: "스무고개로 사건을 푸는 꼬마 탐정의 추리." }
    ]

    # 초등 5~6 (고학년) — 장편 동화·성장 소설.
    high = [
      { title: "마당을 나온 암탉", author: "황선미", publisher: "사계절", summary: "자유를 꿈꾸는 암탉 잎싹의 감동적인 성장 이야기." },
      { title: "몽실 언니", author: "권정생", publisher: "창비", summary: "전쟁과 가난 속에서도 동생들을 지켜 낸 몽실이의 이야기." },
      { title: "초정리 편지", author: "배유안", publisher: "창비", summary: "훈민정음을 배우며 성장하는 장이의 이야기." },
      { title: "문제아", author: "박기범", publisher: "창비", summary: "어린이의 시선으로 세상을 바라본 단편 모음." },
      { title: "괭이부리말 아이들", author: "김중미", publisher: "창비", summary: "가난한 동네 아이들의 우정과 희망을 그린 이야기." },
      { title: "푸른 사자 와니니", author: "이현", publisher: "창비", summary: "초원에서 살아남는 어린 사자 와니니의 모험." },
      { title: "해리엇", author: "한윤섭", publisher: "문학동네", summary: "거북이 해리엇의 눈으로 본 생명과 자유." },
      { title: "봉주르, 뚜르", author: "한윤섭", publisher: "문학동네", summary: "프랑스 작은 마을에서 펼쳐지는 우정과 비밀." },
      { title: "우리들의 일그러진 영웅", author: "이문열", publisher: "다림", summary: "교실 권력을 통해 사회를 비추는 성장 소설." },
      { title: "기억 전달자", author: "로이스 로리", publisher: "비룡소", summary: "완벽해 보이는 사회의 비밀을 알게 된 소년의 이야기." },
      { title: "사자와 마녀와 옷장", author: "C. S. 루이스", publisher: "시공주니어", summary: "옷장 너머 나니아에서 펼쳐지는 모험." },
      { title: "아홉 살 인생", author: "위기철", publisher: "청년사", summary: "산동네 아홉 살 여민이가 바라본 세상과 사람들." },
      { title: "책과 노니는 집", author: "이영서", publisher: "문학동네", summary: "책방 심부름꾼 장이의 눈으로 본 조선의 책 이야기." },
      { title: "너도 하늘말나리야", author: "이금이", publisher: "밤티", summary: "세 아이가 서로를 보듬으며 자라는 성장 이야기." },
      { title: "소리 질러, 운동장", author: "진형민", publisher: "창비", summary: "규칙에 얽매이지 않는 아이들의 야구 이야기." },
      { title: "빨간 머리 앤", author: "루시 모드 몽고메리", publisher: "인디고", summary: "상상력 넘치는 소녀 앤의 성장과 우정." },
      { title: "수일이와 수일이", author: "김우경", publisher: "우리교육", summary: "가짜 나와 진짜 나 사이에서 벌어지는 소동." },
      { title: "몬스터 콜스", author: "패트릭 네스", publisher: "웅진주니어", summary: "괴물을 만나 슬픔과 마주하는 소년의 이야기." },
      { title: "안네의 일기", author: "안네 프랑크", publisher: "책과함께어린이", summary: "은신처에서 써 내려간 소녀의 진솔한 기록." },
      { title: "곰이와 오푼돌이 아저씨", author: "권정생", publisher: "보리", summary: "분단의 아픔을 어린이의 눈으로 그린 이야기." },
      { title: "나의 라임오렌지나무", author: "J. M. 바스콘셀로스", publisher: "동녘", summary: "가난 속에서도 상상으로 세상을 견디는 제제." },
      { title: "책 먹는 여우", author: "프란치스카 비어만", publisher: "주니어김영사", summary: "책을 먹어 치우다 작가가 된 여우 씨 이야기." },
      { title: "긴긴밤", author: "루리", publisher: "문학동네", summary: "홀로 남은 코뿔소와 펭귄이 함께한 긴 여정." },
      { title: "불량한 자전거 여행", author: "김남중", publisher: "창비", summary: "자전거로 전국을 달리며 성장하는 소년의 여행기." }
    ]

    # 고전 — 세대를 넘어 읽히는 명작(밴드 지정).
    classics = [
      { title: "어린 왕자", author: "앙투안 드 생텍쥐페리", publisher: "열린책들", summary: "사막에서 만난 어린 왕자와의 이야기.", band: band_high },
      { title: "오즈의 마법사", author: "라이먼 프랭크 바움", publisher: "비룡소", summary: "회오리바람에 실려 오즈로 간 도로시의 모험.", band: band_mid },
      { title: "이상한 나라의 앨리스", author: "루이스 캐럴", publisher: "비룡소", summary: "토끼 굴로 떨어져 만난 이상한 나라 이야기.", band: band_mid },
      { title: "톰 소여의 모험", author: "마크 트웨인", publisher: "시공주니어", summary: "장난꾸러기 톰의 강가 모험 이야기.", band: band_high },
      { title: "소공녀", author: "프랜시스 호지슨 버넷", publisher: "시공주니어", summary: "역경 속에서도 품위를 잃지 않은 세라의 이야기.", band: band_high },
      { title: "비밀의 화원", author: "프랜시스 호지슨 버넷", publisher: "시공주니어", summary: "버려진 정원을 되살리며 자라는 아이들의 이야기.", band: band_high },
      { title: "키다리 아저씨", author: "진 웹스터", publisher: "인디고", summary: "얼굴 모를 후원자에게 편지를 쓰는 주디의 이야기.", band: band_high },
      { title: "작은 아씨들", author: "루이자 메이 올콧", publisher: "펭귄클래식코리아", summary: "네 자매의 사랑과 성장을 그린 고전.", band: band_high },
      { title: "15소년 표류기", author: "쥘 베른", publisher: "비룡소", summary: "무인도에 표류한 소년들의 생존 모험.", band: band_high },
      { title: "홍길동전", author: "허균", publisher: "창비", summary: "차별에 맞서 활빈당을 이끈 홍길동 이야기.", band: band_high },
      { title: "피노키오", author: "카를로 콜로디", publisher: "비룡소", summary: "거짓말하면 코가 자라는 나무 인형의 모험.", band: band_mid },
      { title: "플랜더스의 개", author: "위다", publisher: "시공주니어", summary: "화가를 꿈꾸는 소년 넬로와 개 파트라슈의 우정.", band: band_mid },
      { title: "행복한 왕자", author: "오스카 와일드", publisher: "시공주니어", summary: "제비와 함께 나눔을 실천한 왕자 동상 이야기.", band: band_mid },
      { title: "허클베리 핀의 모험", author: "마크 트웨인", publisher: "시공주니어", summary: "강을 따라 자유를 찾아 떠나는 허크의 여정.", band: band_high }
    ]

    upsert = lambda do |attrs, category, band|
      book = Book.find_or_initialize_by(title: attrs[:title], author: attrs[:author])
      book.publisher = attrs[:publisher]
      book.summary = attrs[:summary]
      book.grade_band = band
      book.category = category
      book.save!
    end

    low.each  { |attrs| upsert.call(attrs, :recommended, band_low) }
    mid.each  { |attrs| upsert.call(attrs, :recommended, band_mid) }
    high.each { |attrs| upsert.call(attrs, :recommended, band_high) }
    classics.each { |attrs| upsert.call(attrs, :classic, attrs[:band] || band_high) }

    puts "Seeded books. recommended=#{Book.recommended.count} classic=#{Book.classic.count} total=#{Book.count}"
  end

  desc "Enrich catalog books with cover/isbn/publisher via Naver (manual, networked; no-op without key)"
  task enrich: :environment do
    updated = Books::CatalogEnricher.new.enrich_all
    if Books::SearchService.available?
      puts "books:enrich — updated #{updated} catalog books."
    else
      puts "books:enrich skipped — no Naver keys (offline). Catalog keeps curated fields."
    end
  end
end
