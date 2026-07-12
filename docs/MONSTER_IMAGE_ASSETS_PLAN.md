# 몬스터 이미지 에셋 72종 앱 반영 계획

> 작성·적용: 2026-07-12 · 상태: **구현 완료** · 관련 TODO: [`TODO.md`](../TODO.md) 「🟡 콘텐츠·데이터 완성 › 몬스터 이미지 에셋」
> 결정: 포맷 **WebP**(생성물 그대로) · 범위 **에셋 배치 + 뷰 연결(완결)**

## Context (왜 이 작업을 하는가)

`script/output/` 에 72종 몬스터 스프라이트(24라인 × 3폼)가 **애니메이션 WebP**로 생성 완료됐다.
그러나 앱은 아직 이 에셋을 전혀 쓰지 못한다:

- 몬스터 뷰 4곳이 실제 이미지 대신 **이모지 플레이스홀더**(`monster_emoji`)를 렌더 중 — `app/assets/images/monsters/` 폴더 자체가 없음(`.keep`만).
- `TODO.md` 「몬스터 이미지 에셋」 항목이 미완: *"image_key 참조만 있고 실제 PNG 없음(뷰는 플레이스홀더)"*.

**두 가지 불일치**를 해소해야 앱에 반영된다:
1. **파일명**: 생성물은 `script/output/webp/NN_NN.webp`(dex_no_stage, 예 `01_01.webp`)인데, 앱은 `monster_species.image_key` = **슬러그**(`pup_1`, `hedgehog_2`, `dragon_3`)를 파일 stem으로 기대한다.
2. **포맷**: 설계 문서 3종이 "투명 PNG"로 적혀 있으나 실제 생성물은 애니메이션 WebP.

**결정:** 포맷은 **WebP**로 확정(생성물 그대로, 문서를 WebP로 동기화). 범위는 **에셋 배치 + 뷰 연결** — 화면에 실제로 보이게 한다.

**의도한 결과:** 도감·상세·대표몬스터·진화 로드맵에서 이모지 대신 72종 애니메이션 WebP가 렌더되고, 에셋이 없는 폼은 이모지로 무중단 폴백된다.

---

## 핵심 사실 (탐색으로 확인됨)

- **소스(권장)**: `script/output/webp/NN_NN.webp` — 72개 flat 파일, `NN`=dex_no(01–24), 다음 `NN`=stage(01–03). 각 라인 폴더(`01/03_전설멍/…`)의 webp와 바이트 동일한 사본. (frame_*.png·sprite.png·raw.png은 중간 산출물, 앱에는 불필요.)
- **매핑 근거**: `db/seeds/monsters.yml` 의 `monster_lines[].dex_no` + `forms[].{stage,key,name}`. `MonsterSeeder`(`app/services/monster_seeder.rb:74`)가 `image_key = form["key"]` 로 적재 → **image_key ≡ 슬러그 key** (테스트 `test/models/monster_seed_integrity_test.rb:64` 확인).
- **대상 경로**: `app/assets/images/monsters/<image_key>.webp` (Propshaft가 `image_tag "monsters/<key>.webp"` 로 해석). 폴더는 신규 생성.
- **현재 렌더(이모지)**: `app/helpers/monsters_helper.rb#monster_emoji`(슬러그의 `_\d+` 접미 제거 → 종별 이모지). 사용처 4곳:
  - `app/views/monsters/_active_monster.html.erb:8-10` (항상 렌더, `data-monster-care-target="sprite"` 스팬)
  - `app/views/monsters/_monster_card.html.erb:9-11` (`owned ? emoji : "❔"`)
  - `app/views/monsters/_detail.html.erb:6-8` (`user_monster ? emoji : "❔"`, `sprite` 타깃 스팬)
  - `app/views/monsters/_evolution_roadmap.html.erb:8` (`reached ? emoji : "❔"`)
- **JS 무영향**: `app/javascript/controllers/monster_care_controller.js` 는 `sprite` 타깃에 `animate-bounce` 클래스만 토글 — img로 바꿔도 그대로 동작. WebP는 `<img>`만으로 무한 재생(JS 불필요).
- **git**: `script/output/**` 는 이미 추적 중(1152 파일). `.gitignore` 는 `app/assets/images/` 를 무시하지 않음 → 배치한 72 webp(~30MB)는 정상 커밋됨.
- **rake 관례**: `lib/tasks/monsters.rake` 에 `monsters:seed`/`seed_phase2` 존재 → 에셋 설치 태스크를 같은 파일에 추가.

---

## 구현 계획

### A. 에셋 배치 — rake 태스크 (멱등·재현 가능)

`lib/tasks/monsters.rake` 에 `monsters:install_assets` 추가:

- `db/seeds/monsters.yml` 를 YAML 로드 → 각 `(dex_no, form.stage, form.key, form.name)` 순회.
- 소스: `script/output/webp/#{'%02d'%dex_no}_#{'%02d'%stage}.webp`.
- **안전 검증**: 정확히 72폼인지, 키가 유효·고유한지, 소스 파일과 `script/output/#{'%02d'%dex_no}/#{'%02d'%stage}_#{name}/` 라인 폴더가 모두 존재하는지 복사 전에 일괄 검증한다. 하나라도 틀리면 부분 설치 없이 실패한다.
- 대상: `app/assets/images/monsters/#{key}.webp` 로 `FileUtils.cp`(디렉터리 없으면 생성). 재실행 안전.
- 종료 시 `copied/skipped/총 72` 리포트 출력. (desc 도 추가.)

> 소스(`script/output`)는 마스터/디버그 세트로 그대로 두고 앱 런타임 세트(`app/assets`)로 **복사**한다. Phase 2 재생성 시 태스크 재실행만으로 갱신.

### B. 뷰 연결 — 헬퍼 + partial 4곳

**B-1. 헬퍼 신설** `app/helpers/monsters_helper.rb` 에 `monster_sprite`:

```ruby
# 슬러그 에셋(monsters/<key>.webp)이 있으면 애니메이션 <img>, 없으면 이모지 폴백.
def monster_sprite(species_or_key, img_class: "h-full w-full object-contain", **html_options)
  key = if species_or_key.respond_to?(:image_key) && species_or_key.image_key.present?
    species_or_key.image_key
  elsif species_or_key.respond_to?(:key)
    species_or_key.key
  else
    species_or_key.to_s
  end
  logical_path = "monsters/#{key}.webp"

  return monster_emoji(species_or_key) unless monster_asset_exists?(logical_path)

  default_alt = species_or_key.respond_to?(:name) ? species_or_key.name : ""
  image_tag logical_path,
            { alt: default_alt, class: img_class, loading: "lazy" }.merge(html_options)
end

def monster_asset_exists?(logical_path)
  Rails.application.assets.load_path.find(logical_path).present?
rescue StandardError
  false
end
```

- 폴백 시 **기존 이모지 문자열 그대로 반환** → 호출부의 사이즈 스팬(text-5xl 등)이 이모지를 감싸므로 시각적 회귀 없음.
- 이미지일 때는 `img_class` 로 픽셀 크기 지정(스팬의 font-size 무관).
- 잠금/미발견(`"❔"`) 분기는 **변경하지 않음** — 보유/도달한 폼만 스프라이트로 교체.

**B-2. partial 교체(각 스팬/타깃·분기 유지, 안쪽 `monster_emoji(x)` → `monster_sprite(x, img_class:)` 만 치환):**
- `_active_monster.html.erb`: `monster_emoji(monster.species)` → `monster_sprite(monster.species, img_class: "w-14 h-14")` (스팬의 `data-monster-care-target="sprite"` 유지).
- `_detail.html.erb`: `user_monster ?` 참일 때 `monster_sprite(current_species, img_class: "w-20 h-20")` (sprite 타깃 유지).
- `_monster_card.html.erb`: `owned ?` 참일 때 `monster_sprite(species, img_class: "w-12 h-12")`.
- `_evolution_roadmap.html.erb`: `reached ?` 참일 때 `monster_sprite(species, img_class: "w-10 h-10")`.

(크기 클래스는 기존 이모지 스케일(text-6xl/5xl/4xl/3xl)에 상응하게 조정 — 구현 시 화면 확인하며 미세조정.)

### C. 문서·CLAUDE.md 동기화 (WebP 확정 반영 — 프로젝트 유지보수 규칙)

- `docs/monsters.md` §3.1(≈`:47-49`): "투명 PNG 1024×1024" 및 `pup_1.png` → **애니메이션 WebP**, 경로 `app/assets/images/monsters/pup_1.webp` 로 갱신. §5 "key=image_key" 유지.
- `docs/RAILS_PLAN.md:420` + §13.5(≈`:748-778`): `image_key … 투명 PNG` → 애니메이션 WebP.
- `DESIGN.md:625,785`: 몬스터 이미지 "투명 PNG" → WebP(카드 중앙 배치·잠금 점선 서술은 유지).
- `app/helpers/monsters_helper.rb` 헤더 주석("시드 이미지 자산이 없어 이모지로 대체") → "에셋 있으면 WebP, 없으면 이모지 폴백"으로 수정.
- `app/helpers/CLAUDE.md`: `monsters_helper` 설명에 `monster_sprite`(에셋 렌더+폴백) 추가.
- `lib/tasks/CLAUDE.md`: `monsters.rake` 항목에 `monsters:install_assets`(webp 에셋 설치) 추가.
- `docs/CLAUDE.md`: 이 계획 문서 링크를 인덱스에 추가(선택).
- `TODO.md`: 「몬스터 이미지 에셋」 항목을 `[x]` 완료로 갱신(WebP·경로·태스크 명시).

### D. 테스트

- `test/models/monster_seed_integrity_test.rb`(또는 신규 `monster_asset_presence_test.rb`)에 케이스 추가: 모든 `MonsterSpecies` 에 대해 `app/assets/images/monsters/#{image_key}.webp` 파일 존재 assert(72종 커버리지·드리프트 방지).
- (선택) 헬퍼 테스트: 에셋 존재 시 `<img>`, 미존재 슬러그 시 이모지 폴백 반환.

---

## dex_no → 슬러그 매핑 (참조; 태스크는 monsters.yml에서 자동 도출)

`1 pup · 2 parrot · 3 pencil · 4 fox · 5 cat · 6 owl · 7 robot · 8 turtle · 9 hamster · 10 whale · 11 rabbit · 12 deer · 13 bear · 14 chick · 15 penguin · 16 dino · 17 hedgehog · 18 frog · 19 squirrel · 20 mushroom · 21 unicorn · 22 butterfly · 23 dokkaebi · 24 dragon`
→ 파일명 = `{prefix}_{stage}` (예: `webp/06_02.webp` → `owl_2.webp`, `webp/24_03.webp` → `dragon_3.webp`).

---

## 수정/신설 파일 요약

- **신설 로직**: `lib/tasks/monsters.rake`(태스크 추가), `app/helpers/monsters_helper.rb`(`monster_sprite`/`monster_asset_exists?`).
- **뷰 4곳**: `app/views/monsters/_active_monster.html.erb`·`_detail.html.erb`·`_monster_card.html.erb`·`_evolution_roadmap.html.erb`.
- **에셋 생성**: `app/assets/images/monsters/*.webp` (rake 실행 산출, 72개).
- **문서**: `docs/monsters.md`·`docs/RAILS_PLAN.md`·`DESIGN.md`·`TODO.md`·`app/helpers/CLAUDE.md`·`lib/tasks/CLAUDE.md`·`monsters_helper.rb` 주석.
- **테스트**: 몬스터 에셋 존재 검증 케이스.

---

## 검증 결과

1. `bin/rails monsters:install_assets` 첫 실행 → `copied 72, skipped 0, total 72`; 재실행 → `copied 0, skipped 72, total 72`.
2. `app/assets/images/monsters/*.webp` → 정확히 **72개**, 전 파일에서 WebP `ANIM` 청크 확인.
3. `bin/rails test` → **678 runs, 3891 assertions, 0 failures, 0 errors**.
4. `bin/rubocop` → **308 files, no offenses**; `bin/brakeman --no-pager` → **0 warnings**.
5. production 환경의 Propshaft load path에서 `monsters/pup_1.webp` 탐색 성공.
6. 실제 브라우저에서의 네 화면 육안 확인과 크기 미세조정은 별도 수동 확인 항목으로 남긴다.
