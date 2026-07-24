# frozen_string_literal: true

# Build a project-ready elementary reading catalog from Data4Library's
# grade-specific popular-loan API, NLCY librarian recommendations, and the
# app's curated Book catalog.
#
# Usage:
#   bin/rails runner script/build_elementary_books_tsv.rb
#
# Optional environment variables:
#   BOOKS_FROM=2025-07-17 BOOKS_TO=2026-07-16 BOOKS_LIMIT=5000

require "csv"
require "json"
require "nokogiri"
require "stringio"
require "zip"
require_relative "book_genre_inference"

OUTPUT_PATH = Rails.root.join("db/seeds", "elementary_books.tsv")
SOURCE_URL = "https://data4library.kr/loanDataL"
NLCY_SOURCE_URL = "https://www.nlcy.go.kr/NLCY/contents/C10600000000.do"
NLCY_EXCEL_PATH = "/NLCY/board/C10600000000_suggestBookListExcel.do"
SOURCE_FROM = ENV.fetch("BOOKS_FROM", "2025-07-17")
SOURCE_TO = ENV.fetch("BOOKS_TO", "2026-07-16")
PER_BAND_LIMIT = Integer(ENV.fetch("BOOKS_LIMIT", "5000"), 10)

BANDS = {
  "a8" => "초등 1~2",
  "a10" => "초등 3~4",
  "a12" => "초등 5~6"
}.freeze

KDC_GENRES = {
  "0" => "총류·정보",
  "1" => "철학·심리",
  "2" => "종교·신화",
  "3" => "사회·문화",
  "4" => "자연과학",
  "5" => "기술·생활과학",
  "6" => "예술·체육",
  "7" => "언어",
  "8" => "문학",
  "9" => "역사·지리"
}.freeze

NLCY_SUBJECT_GENRES = {
  "총류" => "총류·정보",
  "철학" => "철학·심리",
  "종교" => "종교·신화",
  "사회과학" => "사회·문화",
  "순수과학" => "자연과학",
  "기술과학" => "기술·생활과학",
  "예술" => "예술·체육",
  "언어" => "언어",
  "문학" => "문학",
  "역사" => "역사·지리"
}.freeze

# Original-publication dates are not present in the popular-loan response.
# This conservative title rule only marks widely established classics; all
# other rows remain "비고전" or "검토필요" rather than being guessed as classics.
CLASSIC_TITLES = %w[
    어린왕자 오즈의마법사 이상한나라의앨리스 거울나라의앨리스 톰소여의모험
    허클베리핀의모험 소공녀 소공자 비밀의화원 키다리아저씨 작은아씨들
    15소년표류기 십오소년표류기 피노키오 플랜더스의개 행복한왕자 빨간머리앤
    안네의일기 보물섬 로빈슨크루소 걸리버여행기 해저2만리 해저이만리
    80일간의세계일주 팔십일간의세계일주 삼총사 레미제라블 장발장 모비딕
    백경 정글북 하이디 폴리아나 올리버트위스트 크리스마스캐럴 돈키호테
    이솝우화 천일야화 아라비안나이트 파랑새 닐스의모험 피터팬 왕자와거지
    지킬박사와하이드 프랑켄슈타인 로미오와줄리엣 베니스의상인 햄릿 맥베스
    홍길동전 춘향전 심청전 흥부전 토끼전 별주부전 장화홍련전 콩쥐팥쥐
    금오신화 구운몽 사씨남정기 양반전 허생전 박씨전 전우치전 임진록
    옹고집전 운영전 최고운전 한중록 난중일기 삼국유사 삼국사기
].freeze

CLASSIC_AUTHOR_PATTERN = Regexp.union(
  %w[
    생텍쥐페리 라이먼프랭크바움 루이스캐럴 마크트웨인 프랜시스호지슨버넷
    진웹스터 루이자메이올콧 쥘베른 카를로콜로디 오스카와일드 몽고메리
    안네프랑크 로버트루이스스티븐슨 대니얼디포 조너선스위프트 알렉상드르뒤마
    빅토르위고 허먼멜빌 러디어드키플링 요한나슈피리 찰스디킨스 세르반테스
    셰익스피어 허균 김만중 박지원 김시습 일연 이순신
  ].map { |author| /#{Regexp.escape(author)}/ }
)

TOPIC_RULES = {
  "우정" => /친구|우정|짝꿍/,
  "가족" => /가족|엄마|아빠|할머니|할아버지|형제|자매/,
  "학교" => /학교|교실|선생님|반장|공부/,
  "동물" => /동물|고양이|강아지|개|새|곰|여우|호랑이|사자|공룡|곤충|물고기/,
  "자연·환경" => /자연|환경|생태|기후|지구|바다|숲|식물|날씨/,
  "과학" => /과학|수학|물리|화학|생물|실험|발명|인체|뇌|의학/,
  "우주" => /우주|별|행성|달|태양|로켓|외계/,
  "역사" => /역사|한국사|세계사|조선|고려|삼국|전쟁|독립/,
  "사회" => /사회|경제|법|정치|인권|평등|민주|평화|문화/,
  "예술" => /미술|그림|음악|노래|춤|영화|사진|예술/,
  "스포츠" => /운동|축구|야구|농구|수영|스포츠/,
  "모험" => /모험|탐험|여행|표류|탈출|생존/,
  "판타지" => /마법|마녀|요정|괴물|몬스터|유령|도깨비|용|판타지/,
  "추리" => /탐정|추리|사건|미스터리|수수께끼/,
  "감정·성장" => /마음|감정|용기|걱정|불안|행복|슬픔|성장|꿈/
}.freeze

HEADERS = %w[
  id title author publisher publication_year isbn13 project_category selection_type
  volume cover_url source_detail_url
  recommendation_month official_audience official_subject official_theme grade_basis
  primary_grade_band grade_bands rank_g12 rank_g34 rank_g56 loans_g12 loans_g34 loans_g56
  classic_status classic_basis genre kdc_code kdc_path content_type monster_element
  topic_tags series_likelihood source_name source_url source_period source_rank_basis
  classification_confidence review_needed notes
].freeze

def clean(value)
  value.to_s.gsub(/[\t\r\n]+/, " ").squeeze(" ").strip
end

def normalized(value)
  clean(value).downcase.gsub(/[^[:alnum:]가-힣]/, "")
end

def valid_isbn13?(value)
  digits = value.to_s.gsub(/\D/, "")
  return false unless digits.length == 13

  sum = digits.chars.each_with_index.sum { |char, index| char.to_i * (index.even? ? 1 : 3) }
  (sum % 10).zero?
end

def genre_for(kdc_code, kdc_path)
  source_genre = clean(kdc_path).split(">").first.presence
  KDC_GENRES[kdc_code.to_s[0]] || NLCY_SUBJECT_GENRES[source_genre] || source_genre || "미분류"
end

def content_type_for(row)
  text = "#{row[:title]} #{row[:author]} #{row[:kdc_path]}"
  return "학습만화·만화" if text.match?(/만화|코믹|comic/i)
  return "문학" if row[:genre] == "문학"
  return "비문학" unless row[:genre] == "미분류"

  "미분류"
end

def topics_for(row)
  text = "#{row[:title]} #{row[:kdc_path]}"
  TOPIC_RULES.filter_map { |tag, pattern| tag if text.match?(pattern) }.join(";")
end

def element_for(row)
  topics = row[:topic_tags].split(";")
  return "nature" if (topics & [ "동물", "자연·환경", "과학" ]).any?
  return "adventure" if (topics & [ "모험", "추리", "스포츠" ]).any?
  return "imagination" if (topics & [ "판타지", "우주" ]).any?
  return "emotion" if (topics & [ "우정", "가족", "감정·성장", "예술" ]).any?
  return "story" if row[:genre] == "문학"

  "knowledge"
end

def inferred_classic?(title, author)
  base_title = clean(title).split(/\s*[:：]\s*/, 2).first
  CLASSIC_TITLES.include?(normalized(base_title)) || normalized(author).match?(CLASSIC_AUTHOR_PATTERN)
end

def series_likelihood(title)
  text = clean(title)
  text.match?(/(?:^|[ .:_-])(?:\d{1,3}|[IVX]{1,5})(?:권|편|화|$)|시리즈|전집/i) ? "가능성높음" : "미확인"
end

def fetch_band(key, age_code)
  page_size = [ PER_BAND_LIMIT, 500 ].min
  page = 1
  documents = []
  connection = Faraday.new(
    url: Library::Data4libraryService::BASE_URL,
    request: { open_timeout: 15, timeout: 120 }
  )

  while documents.size < PER_BAND_LIMIT
    requested = [ page_size, PER_BAND_LIMIT - documents.size ].min
    response = connection.get("/api/loanItemSrch", {
      authKey: key,
      format: "json",
      pageNo: page,
      pageSize: requested,
      startDt: SOURCE_FROM,
      endDt: SOURCE_TO,
      age: age_code
    })
    raise "Data4Library HTTP #{response.status} for #{age_code} page #{page}" unless response.success?

    payload = JSON.parse(response.body)
    batch = payload.dig("response", "docs").to_a.map { |entry| entry.fetch("doc", entry) }
    documents.concat(batch)
    break if batch.size < requested

    page += 1
  end

  documents.first(PER_BAND_LIMIT)
end

def xlsx_cell_value(cell, shared_strings)
  if cell["t"] == "inlineStr"
    cell.xpath(".//*[local-name()='t']").map(&:text).join
  else
    value = cell.at_xpath("./*[local-name()='v']")&.text.to_s
    cell["t"] == "s" ? shared_strings[value.to_i] : value
  end
end

def fetch_nlcy_recommendations
  connection = Faraday.new(
    url: "https://www.nlcy.go.kr",
    request: { open_timeout: 15, timeout: 120 }
  )
  response = connection.get(NLCY_EXCEL_PATH, { schOpt2: "-", bcid: "nlcy_normal08", schBdcode: "" })
  raise "NLCY recommendations HTTP #{response.status}" unless response.success?

  parsed_rows = []
  Zip::File.open_buffer(StringIO.new(response.body)) do |archive|
    strings_xml = Nokogiri::XML(archive.read("xl/sharedStrings.xml"))
    shared_strings = strings_xml.xpath("//*[local-name()='si']").map do |item|
      item.xpath(".//*[local-name()='t']").map(&:text).join
    end
    sheet = Nokogiri::XML(archive.read("xl/worksheets/sheet1.xml"))
    sheet.xpath("//*[local-name()='row']").drop(1).each do |xml_row|
      cells = xml_row.xpath("./*[local-name()='c']").to_h do |cell|
        column = cell["r"].to_s[/\A[A-Z]+/]
        [ column, clean(xlsx_cell_value(cell, shared_strings)) ]
      end
      next unless %w[초등저학년 초등고학년].include?(cells["D"])
      next if cells["E"].blank?

      parsed_rows << {
        recommendation_month: cells["B"], theme: cells["C"], audience: cells["D"],
        title: cells["E"], subject: cells["F"], author: cells["G"],
        publisher: cells["H"], publication_year: cells["I"], isbn13: cells["J"],
        call_number: cells["K"]
      }
    end
  end
  parsed_rows
end

service = Library::Data4libraryService.new
abort "DATA4LIBRARY_KEY is not configured" unless service.available?

api_key = service.instance_variable_get(:@api_key)

# Each grade-band query is independent. Three threads keep the download time
# bounded while every band still paginates sequentially and predictably.
band_documents = BANDS.keys.map do |age_code|
  Thread.new { [ age_code, fetch_band(api_key, age_code) ] }
end.map(&:value).to_h
nlcy_recommendations = fetch_nlcy_recommendations

rows_by_key = {}
BANDS.each do |age_code, band|
  band_documents.fetch(age_code).each do |doc|
    isbn = clean(doc["isbn13"]).gsub(/\D/, "")
    title = clean(doc["bookname"])
    next if title.blank?

    identity = valid_isbn13?(isbn) ? "isbn:#{isbn}" : "text:#{normalized(title)}:#{normalized(doc["authors"])}"
    row = (rows_by_key[identity] ||= {
      title: title,
      author: clean(doc["authors"]),
      publisher: clean(doc["publisher"]),
      publication_year: clean(doc["publication_year"]),
      isbn13: valid_isbn13?(isbn) ? isbn : "",
      volume: clean(doc["vol"]),
      cover_url: clean(doc["bookImageURL"]),
      source_detail_url: clean(doc["bookDtlUrl"]),
      kdc_code: clean(doc["class_no"]),
      kdc_path: clean(doc["class_nm"]),
      bands: {},
      selection_types: [ "popular_loan" ],
      curated_category: nil,
      curated_band: nil
    })
    row[:bands][band] = {
      rank: clean(doc["ranking"]).to_i,
      loans: clean(doc["loan_count"]).to_i
    }
  end
end


# Merge the National Library for Children and Young Adults' librarian-curated
# recommendations (2006-present). Their official low/high audience bands do not
# exactly match the project's three bands, so both values and the mapping basis
# are retained explicitly.
nlcy_recommendations.each do |recommendation|
  isbn = clean(recommendation[:isbn13]).gsub(/\D/, "")
  identity = if valid_isbn13?(isbn)
    "isbn:#{isbn}"
  else
    "text:#{normalized(recommendation[:title])}:#{normalized(recommendation[:author])}"
  end
  mapped_band = recommendation[:audience] == "초등저학년" ? "초등 1~2" : "초등 5~6"
  kdc_code = clean(recommendation[:call_number])[/\d{3}(?:\.\d+)?/].to_s

  row = (rows_by_key[identity] ||= {
    title: recommendation[:title], author: recommendation[:author], publisher: recommendation[:publisher],
    publication_year: recommendation[:publication_year], isbn13: valid_isbn13?(isbn) ? isbn : "",
    volume: "", cover_url: "", source_detail_url: "", kdc_code: kdc_code,
    kdc_path: recommendation[:subject], bands: {}, selection_types: [],
    curated_category: nil, curated_band: nil
  })
  row[:selection_types] << "nlcy_librarian_recommendation"
  row[:selection_types].uniq!
  row[:nlcy_band] ||= mapped_band
  row[:recommendation_months] ||= []
  row[:recommendation_months] << recommendation[:recommendation_month]
  row[:recommendation_months].uniq!
  row[:official_audience] ||= []
  row[:official_audience] << recommendation[:audience]
  row[:official_audience].uniq!
  row[:official_subject] ||= recommendation[:subject]
  row[:official_theme] ||= recommendation[:theme]
  row[:kdc_code] = kdc_code if row[:kdc_code].blank?
  row[:kdc_path] = recommendation[:subject] if row[:kdc_path].blank?
end

# Fold the project's hand-curated 97 books into matching popular rows where
# possible. A curated title not present in the popular list becomes its own row.
Book.where(category: [ :recommended, :classic ]).order(:title).find_each do |book|
  title_key = normalized(book.title)
  author_key = normalized(book.author)
  match = rows_by_key.values.find do |row|
    normalized(row[:title]) == title_key &&
      (author_key.blank? || normalized(row[:author]).include?(author_key) || author_key.include?(normalized(row[:author])))
  end

  unless match
    identity = "curated:#{title_key}:#{author_key}"
    match = (rows_by_key[identity] ||= {
      title: clean(book.title), author: clean(book.author), publisher: clean(book.publisher),
      publication_year: "", isbn13: clean(book.isbn), volume: "", cover_url: clean(book.cover_url),
      source_detail_url: "", kdc_code: "", kdc_path: "",
      bands: {}, selection_types: [], curated_category: nil, curated_band: nil
    })
  end

  match[:selection_types] << "project_curated"
  match[:selection_types].uniq!
  match[:curated_category] = book.category
  match[:curated_band] = book.grade_band
end

catalog_rows = rows_by_key.values
catalog_rows.each { |row| row[:genre] = genre_for(row[:kdc_code], row[:kdc_path]) }
genre_inference = Books::GenreInference.new(catalog_rows)
catalog_rows.select { |row| row[:genre] == "미분류" }.each do |row|
  if row[:selection_types].include?("project_curated")
    row[:genre] = "문학"
    row[:genre_inference] = {
      basis: "project_curated_peer_group",
      confidence: 0.95,
      neighbors: []
    }
  else
    result = genre_inference.infer(row)
    row[:genre] = result.genre
    row[:genre_inference] = {
      basis: "weighted_similar_books",
      confidence: result.confidence,
      neighbors: result.neighbors.map(&:first)
    }
  end
end

rows = catalog_rows.map do |row|
  row[:topic_tags] = topics_for(row)
  row[:content_type] = content_type_for(row)
  row[:monster_element] = element_for(row)

  band_order = BANDS.values
  observed_bands = band_order.select { |band| row[:bands].key?(band) }
  best_band = observed_bands.max_by { |band| row.dig(:bands, band, :loans).to_i }
  primary_band = row[:curated_band].presence || best_band || row[:nlcy_band].presence || "검토필요"
  all_bands = ([ row[:curated_band], row[:nlcy_band] ] + observed_bands).compact.uniq.sort_by { |band| band_order.index(band) || 99 }

  curated_classic = row[:curated_category] == "classic"
  rule_classic = inferred_classic?(row[:title], row[:author])
  classic_status = curated_classic || rule_classic ? "고전" : "비고전"
  classic_basis = if curated_classic
    "project_curated"
  elsif rule_classic
    "title_author_rule"
  else
    "no_classic_signal"
  end

  automatic_fields = row[:selection_types] == [ "project_curated" ] ? [] : [ "genre", "content_type", "monster_element", "topic_tags" ]
  review_reasons = []
  genre_inference_data = row[:genre_inference]
  review_reasons << "KDC없음·장르유사도서추정" if genre_inference_data
  review_reasons << "ISBN없음" if row[:isbn13].blank?
  review_reasons << "고전자동판정" if classic_basis == "title_author_rule"
  review_reasons << "공식2단계대상→프로젝트3밴드매핑" if observed_bands.empty? && row[:nlcy_band].present?
  review_reasons << "주제자동분류" if automatic_fields.any?
  inference_notes = if genre_inference_data
    notes = [
      "장르추정근거=#{genre_inference_data[:basis]}",
      "장르추정신뢰=#{genre_inference_data[:confidence].round(2)}"
    ]
    if genre_inference_data[:neighbors].any?
      notes << "유사책=#{genre_inference_data[:neighbors].join(' / ')}"
    end
    notes
  else
    []
  end

  sources = []
  sources << "도서관정보나루 인기대출도서" if row[:selection_types].include?("popular_loan")
  sources << "국립어린이청소년도서관 사서추천도서" if row[:selection_types].include?("nlcy_librarian_recommendation")
  sources << "프로젝트 기존 큐레이션" if row[:selection_types].include?("project_curated")
  source_urls = []
  source_urls << SOURCE_URL if row[:selection_types].include?("popular_loan")
  source_urls << NLCY_SOURCE_URL if row[:selection_types].include?("nlcy_librarian_recommendation")
  source_urls << "db/seeds(lib/tasks/books.rake)" if row[:selection_types].include?("project_curated")
  rank_bases = []
  rank_bases << "학년군별 전국 공공도서관 대출순위" if row[:selection_types].include?("popular_loan")
  rank_bases << "사서 발달단계 추천" if row[:selection_types].include?("nlcy_librarian_recommendation")
  rank_bases << "프로젝트 수동 큐레이션" if row[:selection_types].include?("project_curated")

  grade_basis = if row[:curated_band].present?
    "project_curated"
  elsif best_band.present?
    "data4library_highest_loans"
  elsif row[:nlcy_band].present?
    "nlcy_audience_mapped"
  else
    "review_needed"
  end
  classification_confidence = if genre_inference_data && genre_inference_data[:confidence] < 0.72
    "낮음"
  elsif review_reasons.empty?
    "높음"
  else
    "중간"
  end

  {
    title: row[:title],
    author: row[:author],
    publisher: row[:publisher],
    publication_year: row[:publication_year],
    isbn13: row[:isbn13],
    project_category: classic_status == "고전" ? "classic" : "recommended",
    selection_type: row[:selection_types].join(";"),
    volume: row[:volume],
    cover_url: row[:cover_url],
    source_detail_url: row[:source_detail_url],
    recommendation_month: row[:recommendation_months].to_a.sort.join(";"),
    official_audience: row[:official_audience].to_a.join(";"),
    official_subject: row[:official_subject],
    official_theme: row[:official_theme],
    grade_basis: grade_basis,
    primary_grade_band: primary_band,
    grade_bands: all_bands.join(";"),
    rank_g12: row.dig(:bands, "초등 1~2", :rank),
    rank_g34: row.dig(:bands, "초등 3~4", :rank),
    rank_g56: row.dig(:bands, "초등 5~6", :rank),
    loans_g12: row.dig(:bands, "초등 1~2", :loans),
    loans_g34: row.dig(:bands, "초등 3~4", :loans),
    loans_g56: row.dig(:bands, "초등 5~6", :loans),
    classic_status: classic_status,
    classic_basis: classic_basis,
    genre: row[:genre],
    kdc_code: row[:kdc_code],
    kdc_path: row[:kdc_path],
    content_type: row[:content_type],
    monster_element: row[:monster_element],
    topic_tags: row[:topic_tags],
    series_likelihood: series_likelihood(row[:title]),
    source_name: sources.join(";"),
    source_url: source_urls.join(";"),
    source_period: row[:selection_types].include?("popular_loan") ? "#{SOURCE_FROM}~#{SOURCE_TO}" : "",
    source_rank_basis: rank_bases.join(";"),
    classification_confidence: classification_confidence,
    review_needed: review_reasons.empty? ? "아니오" : "예",
    notes: (review_reasons + inference_notes).join(";")
  }
end

rows.sort_by! do |row|
  best_rank = [ row[:rank_g12], row[:rank_g34], row[:rank_g56] ].compact.min || 999_999
  [ best_rank, row[:title], row[:isbn13] ]
end

CSV.open(OUTPUT_PATH, "w", col_sep: "\t", row_sep: "\n", encoding: "UTF-8") do |tsv|
  tsv << HEADERS
  rows.each_with_index do |row, index|
    tsv << HEADERS.map { |header| header == "id" ? format("EB%05d", index + 1) : clean(row[header.to_sym]) }
  end
end

puts "Wrote #{rows.size} deduplicated books to #{OUTPUT_PATH}"
puts "Source rows by grade band: #{BANDS.values.map { |band| "#{band}=#{rows_by_key.values.count { |row| row[:bands].key?(band) }}" }.join(", ")}"
