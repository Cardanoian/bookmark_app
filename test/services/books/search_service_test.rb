require "test_helper"

class Books::SearchServiceTest < ActiveSupport::TestCase
  # 스텁 Faraday 연결(네트워크 차단). 각 제공자별 path 를 스텁한다.
  def stub_connection(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new { |faraday| faraday.adapter :test, stubs }
  end

  test "available? is false when both keys are blank (placeholder credentials)" do
    service = Books::SearchService.new(kakao_key: "", naver_id: "", naver_secret: "")
    assert_not service.available?
  end

  test "available? is true when a kakao key is present" do
    service = Books::SearchService.new(kakao_key: "K", naver_id: "", naver_secret: "")
    assert service.available?
  end

  test "kakao success normalizes results and caches them as searched books" do
    connection = stub_connection do |stub|
      stub.get("/v3/search/book") do
        [ 200, {}, {
          "documents" => [ {
            "title" => "카카오책", "authors" => [ "김작가", "이작가" ], "publisher" => "카카오출판",
            "thumbnail" => "http://img/kakao", "isbn" => "1111111111 9781111111111", "contents" => "카카오 설명"
          } ]
        }.to_json ]
      end
    end
    service = Books::SearchService.new(kakao_key: "K", kakao_connection: connection)

    results = service.call("카카오")

    assert_equal 1, results.size
    assert_equal "카카오책", results.first[:title]
    assert_equal "김작가, 이작가", results.first[:author]
    assert_equal "9781111111111", results.first[:isbn]

    cached = Book.searched.find_by(isbn: "9781111111111")
    assert cached, "expected the kakao result to be cached as a searched book"
    assert_equal "카카오책", cached.title
  end

  test "falls back to naver when kakao fails" do
    kakao = stub_connection { |stub| stub.get("/v3/search/book") { [ 500, {}, "server error" ] } }
    naver = stub_connection do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, {
          "items" => [ {
            "title" => "네이버책", "author" => "박작가", "publisher" => "네이버출판",
            "image" => "http://img/naver", "isbn" => "9782222222222", "description" => "네이버 설명"
          } ]
        }.to_json ]
      end
    end
    service = Books::SearchService.new(
      kakao_key: "K", naver_id: "N", naver_secret: "S",
      kakao_connection: kakao, naver_connection: naver
    )

    results = service.call("네이버")

    assert_equal 1, results.size
    assert_equal "네이버책", results.first[:title]
    assert Book.searched.exists?(isbn: "9782222222222")
  end

  test "falls back to local cache when both keys are blank (no network)" do
    Book.create!(title: "로컬 어린 왕자", author: "생텍쥐페리", category: :recommended)
    service = Books::SearchService.new(kakao_key: "", naver_id: "", naver_secret: "")

    results = service.call("어린")

    assert_equal 1, results.size
    assert_equal "로컬 어린 왕자", results.first[:title]
  end

  test "returns an empty array for a blank query" do
    assert_equal [], Books::SearchService.new(kakao_key: "K").call("")
  end
end
