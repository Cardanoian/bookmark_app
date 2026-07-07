require "test_helper"

class Books::SearchServiceTest < ActiveSupport::TestCase
  # 스텁 Faraday 연결(네트워크 차단).
  def stub_connection(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new { |faraday| faraday.adapter :test, stubs }
  end

  test "available? is false when the naver keys are blank (placeholder credentials)" do
    assert_not Books::SearchService.new(naver_id: "", naver_secret: "").available?
  end

  test "available? is false when only one naver key is present" do
    assert_not Books::SearchService.new(naver_id: "N", naver_secret: "").available?
    assert_not Books::SearchService.new(naver_id: "", naver_secret: "S").available?
  end

  test "available? is true when both naver keys are present" do
    assert Books::SearchService.new(naver_id: "N", naver_secret: "S").available?
  end

  test "naver success normalizes results and caches them as searched books" do
    connection = stub_connection do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, {
          "items" => [ {
            "title" => "네이버책", "author" => "박작가^김작가", "publisher" => "네이버출판",
            "image" => "http://img/naver", "isbn" => "2222222222 9782222222222", "description" => "네이버 설명"
          } ]
        }.to_json ]
      end
    end
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)

    results = service.call("네이버")

    assert_equal 1, results.size
    assert_equal "네이버책", results.first[:title]
    assert_equal "박작가, 김작가", results.first[:author]
    assert_equal "9782222222222", results.first[:isbn], "공백 구분 ISBN 은 긴 쪽(ISBN13)을 고른다"

    cached = Book.searched.find_by(isbn: "9782222222222")
    assert cached, "네이버 결과는 searched 도서로 캐시돼야 한다"
    assert_equal "네이버책", cached.title
  end

  test "falls back to local cache when naver request fails" do
    Book.create!(title: "로컬 어린 왕자", author: "생텍쥐페리", category: :recommended)
    naver = stub_connection { |stub| stub.get("/v1/search/book.json") { [ 500, {}, "server error" ] } }
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: naver)

    results = service.call("어린")

    assert_equal 1, results.size
    assert_equal "로컬 어린 왕자", results.first[:title]
  end

  test "falls back to local cache when keys are blank (no network)" do
    Book.create!(title: "로컬 어린 왕자", author: "생텍쥐페리", category: :recommended)
    service = Books::SearchService.new(naver_id: "", naver_secret: "")

    results = service.call("어린")

    assert_equal 1, results.size
    assert_equal "로컬 어린 왕자", results.first[:title]
  end

  test "returns an empty array for a blank query" do
    assert_equal [], Books::SearchService.new(naver_id: "N", naver_secret: "S").call("")
  end
end
