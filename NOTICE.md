# 출처 및 라이선스 (NOTICE)

「책갈피」가 사용하는 폰트·이미지·데이터·AI 모델의 출처를 밝힙니다.
앱 화면에서는 **로그인 화면 하단의 "출처·라이선스"**에서 같은 내용을 볼 수 있으며,
오프라인 체험판(`frontend/`)은 첫 화면과 하단 푸터에 같은 표기를 담고 있습니다.

---

## 폰트

### Pretendard
- **저작자**: 길형진(Kil Hyung-jin) — https://github.com/orioncactus/pretendard
- **라이선스**: SIL Open Font License 1.1 (Reserved Font Name: `Pretendard`)
- **라이선스 전문**: [`app/assets/fonts/pretendard/LICENSE.txt`](app/assets/fonts/pretendard/LICENSE.txt)
  — OFL 1.1은 폰트를 재배포할 때 저작권 고지와 라이선스 사본을 함께 배포하도록 요구하므로,
  전문을 폰트 파일과 같은 디렉토리에 둡니다.
- **사용 파일**: `app/assets/fonts/pretendard/PretendardVariable.woff2` (자체 호스팅),
  체험판 사본 `frontend/src/assets/PretendardVariable.woff2`
- **비고**: Pretendard는 Source Sans/Inter/M PLUS 1(모두 OFL 1.1)에서 파생된 폰트이며,
  해당 저작권자 표기는 라이선스 전문 상단에 함께 담겨 있습니다. 파일을 수정하지 않고 그대로 사용합니다.

---

## 이미지

### 반려 몬스터 스프라이트 (72폼 × 정적 PNG + 애니메이션 WebP)
- **위치**: `app/assets/images/monsters/`, 체험판 사본 `frontend/src/assets/monsters/`
- **제작**: **생성형 AI로 제작한 이미지**입니다. Google **Gemini 3.1 Flash Image**로 몬스터별 원본 1장을
  생성한 뒤, 배경 크로마키 제거와 숨쉬기(idle) 프레임 합성을 프로젝트 자체 스크립트
  ([`script/monster_sprite_pipeline.py`](script/monster_sprite_pipeline.py))로 처리했습니다.
- **디자인·기획**: 24개 계열 72폼의 이름·속성·진화 조건·서사는 프로젝트에서 직접 설계했습니다
  (`db/seeds/monsters.yml`, `db/seeds/monster_stories.yml`).

### 빈 화면 일러스트 (13종)
- **위치**: `app/assets/images/empty_states/` (128×128 투명 PNG)
- **제작**: **생성형 AI로 제작한 이미지**입니다. OpenAI **ChatGPT**의 이미지 생성으로 만들었습니다.

### UI 아이콘 · 브랜드 로고
- **위치**: `app/assets/images/ui-icons.svg`(공용 symbol 스프라이트, 57종), `public/icon.png`(브랜드 로고)
- **제작**: **생성형 AI로 제작한 이미지**입니다. OpenAI **ChatGPT**의 이미지 생성으로 만들었습니다.

### 도서 표지 이미지
- **출처**: **네이버 도서 검색 오픈API**(https://openapi.naver.com) 가 제공하는 이미지 URL
- **사용 방식**: 이미지를 내려받아 저장하지 않고, API가 준 원본 주소(`books.cover_url`)를 화면에서
  그대로 참조합니다.
- **저작권**: 각 표지의 저작권은 해당 **출판사·저작권자**에게 있으며, 「책갈피」는 도서 식별을 돕기 위해
  표시할 뿐 어떠한 권리도 주장하지 않습니다.

---

## 데이터

### 도서 정보 검색
- **출처**: 네이버 개발자센터 **검색 API(도서)** — https://developers.naver.com
- **사용 위치**: [`app/services/books/search_service.rb`](app/services/books/search_service.rb)
  (책 제목 자동완성·원격 검색)

### 도서 카탈로그 · 인기 대출 · 인근 도서관 소장/대출 정보
- **출처**: **도서관 정보나루**(data4library) — https://data4library.kr
- **사용 위치**: [`app/services/library/data4library_service.rb`](app/services/library/data4library_service.rb)
  (학년별 인기 대출·도서관 소장 조회), [`script/build_elementary_books_tsv.rb`](script/build_elementary_books_tsv.rb)
  (`db/seeds/elementary_books.tsv` 카탈로그 생성)

### 사서 추천 도서 목록
- **출처**: **국립어린이청소년도서관(NLCY)** 사서 추천 목록 — https://www.nlcy.go.kr
- **사용 위치**: `script/build_elementary_books_tsv.rb` (카탈로그 병합 시 추천 표시)

### 전국 초등학교 정보 (학교명·표준학교코드·주소)
- **출처**: **나이스(NEIS) 교육정보 개방 포털** — https://open.neis.go.kr
- **사용 위치**: [`app/services/schools/neis_fetcher.rb`](app/services/schools/neis_fetcher.rb),
  `lib/tasks/schools.rake` → `db/seeds/schools.csv`

> 위 공공·오픈 데이터는 각 제공기관의 이용약관·이용조건을 따릅니다.
> 원천 데이터의 최신성·정확성은 각 제공기관에 있으며, 「책갈피」는 이를 교육 목적으로 가공해 표시합니다.

---

## AI 모델

- **Anthropic Claude** (`claude-haiku-4-5`) — 독후감 5축 첨삭·퀴즈 초안·게임 콘텐츠 생성.
  https://www.anthropic.com
- **Google Gemini 3.1 Flash Image** — 반려 몬스터 스프라이트 원본 이미지 생성(오프라인 1회성 제작).
- **OpenAI ChatGPT** — 빈 화면 일러스트 및 로고, 아이콘 생성(오프라인 1회성 제작). https://openai.com

AI가 생성한 첨삭 문구는 담임교사의 검토·승인을 거친 뒤에만 학생에게 공개됩니다.

---

## 오픈소스 소프트웨어

「책갈피」는 다음 오픈소스 위에서 동작하며, 각 프로젝트의 라이선스를 따릅니다.
전체 목록과 정확한 버전은 [`Gemfile.lock`](Gemfile.lock) · [`frontend/package-lock.json`](frontend/package-lock.json)에 있습니다.

| 소프트웨어                                                                                              | 용도                              | 라이선스      |
| ------------------------------------------------------------------------------------------------------- | --------------------------------- | ------------- |
| [Ruby on Rails](https://rubyonrails.org)                                                                | 애플리케이션 프레임워크           | MIT           |
| [Hotwire (Turbo · Stimulus)](https://hotwired.dev)                                                      | 프런트엔드 상호작용               | MIT           |
| [Tailwind CSS](https://tailwindcss.com)                                                                 | 스타일 시스템                     | MIT           |
| [Propshaft](https://github.com/rails/propshaft) · [Importmap](https://github.com/rails/importmap-rails) | 자산 파이프라인                   | MIT           |
| [Pundit](https://github.com/varvet/pundit)                                                              | 역할별 인가                       | MIT           |
| [Solid Queue · Solid Cache · Solid Cable](https://github.com/rails)                                     | 잡·캐시·실시간                    | MIT           |
| [Faraday](https://lostisland.github.io/faraday/)                                                        | 외부 API 클라이언트               | MIT           |
| [bcrypt-ruby](https://github.com/bcrypt-ruby/bcrypt-ruby)                                               | 비밀번호 해시                     | MIT           |
| [SQLite](https://sqlite.org)                                                                            | 데이터베이스                      | Public Domain |
| [React](https://react.dev) · [Vite](https://vite.dev)                                                   | 오프라인 체험판(`frontend/`) 빌드 | MIT           |

---

## 문의

출처 표기에 오류가 있거나 저작물 사용 중단을 요청하시려면 저장소 이슈로 알려 주세요.
확인 후 신속히 조치하겠습니다.
