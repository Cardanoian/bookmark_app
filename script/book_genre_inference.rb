# frozen_string_literal: true

require "set"

module Books
  # Infers a broad KDC-compatible genre from already-classified neighboring
  # books. It uses weighted title character n-grams plus series, author, and
  # publisher similarities; it does not call an external API or invent a KDC
  # code. The caller remains responsible for marking the result as inferred.
  class GenreInference
    Result = Data.define(:genre, :confidence, :neighbors, :top_similarity)

    MAX_NEIGHBORS = 12
    COMMON_FEATURE_RATIO = 0.18
    RULE_OVERRIDE_CONFIDENCE = 0.72

    # High-precision signals (proper nouns / domain terms) applied regardless of kNN
    # confidence. Broad topic words that overlap with fiction titles stay in
    # STRONG_GENRE_RULES (confidence-gated). Kept in sync with app/services/books/genre_inference.rb.
    DECISIVE_GENRE_RULES = [
      [ "언어", /맞춤법|받아쓰기|영단어|영문법|한자|어휘력/iu ],
      [ "역사·지리", /한국사|세계사|삼국시대|고조선|고구려|백제|신라|발해|고려시대|조선시대|임진왜란|독립운동|이집트|로마\s*제국|메소포타미아|문명|유적|위인전|세계\s*지리/iu ],
      [ "사회·문화", /민주주의|대통령|국회|선거|헌법|인권|다문화|경제|금융|주식|세금/iu ],
      [ "종교·신화", /성경|기독교|불교|그리스\s*로마\s*신화|북유럽\s*신화|단군\s*신화/iu ],
      [ "철학·심리", /철학|심리학|MBTI/iu ],
      [ "예술·체육", /미술사|음악사|바둑|태권도|올림픽|월드컵/iu ],
      [ "총류·정보", /코딩|프로그래밍|인공지능|로블록스|백과사전|스크래치/iu ],
      [ "자연과학", /물리학|생물학|천문학|곤충도감|식물도감|인체\s*탐험/iu ]
    ].freeze

    STRONG_GENRE_RULES = [
      [ "언어", /맞춤법|받아쓰기|반대말|우리말|한글|국어|영어|영단어|어휘|낱말|문해력|글쓰기|속담|사자성어|관용어|한자/iu ],
      [ "역사·지리", /한국사|세계사|역사|조선|고려|고구려|백제|신라|삼국시대|문화유산|지리|세계\s*여행|위인/iu ],
      [ "사회·문화", /비상계엄|민주주의|대통령|국회|선거|정치|인권|사회|경제|금융|세금|법률|법\b|직업|다문화/iu ],
      [ "종교·신화", /성경|기독교|불교|하나님|예수|종교|그리스\s*로마\s*신화|북유럽\s*신화/iu ],
      [ "철학·심리", /철학|심리|MBTI|감정\s*(?:사전|수업|공부)|마음\s*(?:사전|수업|공부)/iu ],
      [ "예술·체육", /미술사|미술|음악|예술|축구|야구|농구|배구|스포츠|체육|올림픽|마인크래프트|프로게이머/iu ],
      [ "총류·정보", /컴퓨터|코딩|프로그래밍|소프트웨어|인터넷|인공지능|챗GPT|AI\s*(?:시대|수업|공부)/iu ],
      [ "기술·생활과학", /의학|건강|질병|병원|요리|레시피|음식|건축|교통|자동차|로봇|발명/iu ],
      [ "자연과학", /과학|수학|공룡|곤충|동물|식물|생물|물리|화학|지구|우주|자연|인체|생명|멸종|기후|환경/iu ],
      [ "문학", /\b(?:dragon masters|dog man|creepy|novel|story|adventure|fairy tales?)\b/iu ]
    ].freeze

    def initialize(rows)
      @rows = rows.reject { |row| row[:genre].blank? || row[:genre] == "미분류" }
      build_index
    end

    def infer(row)
      vector = weighted_vector(features(row))
      candidates = candidate_scores(vector)
      neighbors = candidates.filter_map do |index, dot_product|
        similarity = cosine_similarity(dot_product, vector, index)
        [ @rows[index], similarity ] if similarity.positive?
      end.sort_by { |_, similarity| -similarity }.first(MAX_NEIGHBORS)

      return fallback_result if neighbors.empty?

      votes = Hash.new(0.0)
      neighbors.each do |neighbor, similarity|
        votes[neighbor[:genre]] += similarity**2
      end
      genre, winning_vote = votes.max_by { |_, vote| vote }
      total_vote = votes.values.sum
      confidence = total_vote.positive? ? winning_vote / total_vote : 0.0
      if (decisive_genre = decisive_rule_genre(row[:title]))
        genre = decisive_genre
        confidence = [ confidence, RULE_OVERRIDE_CONFIDENCE ].max
      elsif (rule_genre = strong_rule_genre(row[:title])) && confidence < RULE_OVERRIDE_CONFIDENCE
        genre = rule_genre
        confidence = [ confidence, RULE_OVERRIDE_CONFIDENCE ].max
      end

      Result.new(
        genre: genre,
        confidence: confidence,
        neighbors: neighbors.first(3).map { |neighbor, similarity| [ neighbor[:title], similarity ] },
        top_similarity: neighbors.first.last
      )
    end

    private

    def build_index
      @feature_sets = @rows.map { |row| features(row) }
      document_frequency = Hash.new(0)
      @feature_sets.each { |set| set.each_key { |feature| document_frequency[feature] += 1 } }

      max_frequency = [ (@rows.size * COMMON_FEATURE_RATIO).ceil, 2 ].max
      @idf = document_frequency.to_h do |feature, frequency|
        value = Math.log((@rows.size + 1.0) / (frequency + 1.0)) + 1.0
        [ feature, frequency > max_frequency ? 0.0 : value ]
      end

      @vectors = @feature_sets.map { |set| weighted_vector(set) }
      @norms = @vectors.map { |vector| vector_norm(vector) }
      @index = Hash.new { |hash, key| hash[key] = [] }
      @vectors.each_with_index do |vector, index|
        vector.each_key { |feature| @index[feature] << index }
      end
      @fallback_genre = @rows.group_by { |row| row[:genre] }.max_by { |_, books| books.size }.first
    end

    def features(row)
      title = normalize(row[:title])
      base_title = normalize(row[:title].to_s.split(/\s*[:：-]\s*/, 2).first)
      series = base_title.gsub(/\d+|제\d+(?:권|편|화)?|[상중하]편?\z/, "")
      features = {}

      character_ngrams(title, 2).each { |gram| features["title2:#{gram}"] = 0.7 }
      character_ngrams(title, 3).each { |gram| features["title3:#{gram}"] = 1.4 }
      title_tokens(row[:title]).each { |token| features["word:#{token}"] = 2.4 }
      features["series:#{series}"] = 7.0 if series.length >= 4

      author_tokens(row[:author]).each { |token| features["author:#{token}"] = 1.8 }
      publisher = normalize(row[:publisher])
      features["publisher:#{publisher}"] = 0.6 if publisher.length >= 2
      features
    end

    def weighted_vector(feature_weights)
      feature_weights.to_h do |feature, weight|
        [ feature, weight * @idf.fetch(feature, 0.0) ]
      end.reject { |_, weight| weight.zero? }
    end

    def candidate_scores(vector)
      scores = Hash.new(0.0)
      vector.each do |feature, query_weight|
        @index.fetch(feature, []).each do |index|
          scores[index] += query_weight * @vectors[index].fetch(feature)
        end
      end
      scores
    end

    def cosine_similarity(dot_product, query_vector, row_index)
      denominator = vector_norm(query_vector) * @norms[row_index]
      denominator.positive? ? dot_product / denominator : 0.0
    end

    def vector_norm(vector)
      Math.sqrt(vector.values.sum { |weight| weight**2 })
    end

    def character_ngrams(text, size)
      chars = text.chars
      return [] if chars.size < size

      chars.each_cons(size).map(&:join).uniq
    end

    def title_tokens(value)
      value.to_s.downcase.scan(/[[:alnum:]가-힣]{2,}/).reject { |token| token.match?(/\A\d+\z/) }.uniq
    end

    def author_tokens(value)
      value.to_s.scan(/[가-힣]{2,5}|[A-Za-z]{3,}/).map(&:downcase)
           .reject { |token| %w[지은이 글 그림 원작 옮김 감수 기획 저자 공저].include?(token) }
           .uniq
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^[:alnum:]가-힣]/, "")
    end

    def fallback_result
      Result.new(genre: @fallback_genre, confidence: 0.0, neighbors: [], top_similarity: 0.0)
    end

    def decisive_rule_genre(title)
      DECISIVE_GENRE_RULES.find { |_, pattern| title.to_s.match?(pattern) }&.first
    end

    def strong_rule_genre(title)
      STRONG_GENRE_RULES.find { |_, pattern| title.to_s.match?(pattern) }&.first
    end
  end
end
