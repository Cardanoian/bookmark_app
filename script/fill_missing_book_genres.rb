# frozen_string_literal: true

# Fill only blank/미분류 genres in the already-downloaded elementary catalog.
# Existing KDC/NLCY genres are never changed. The replacement is atomic.
#
# Usage:
#   bin/rails runner script/fill_missing_book_genres.rb
#   BOOKS_TSV=/path/to/catalog.tsv bin/rails runner script/fill_missing_book_genres.rb

require "csv"
require "tempfile"
require_relative "book_genre_inference"

path = Pathname(ENV.fetch("BOOKS_TSV", Rails.root.join("db/seeds", "elementary_books.tsv").to_s))
abort "TSV not found: #{path}" unless path.exist?

table = CSV.read(path, col_sep: "\t", headers: true)
rows = table.map { |csv_row| csv_row.to_h.transform_keys(&:to_sym) }
targets = rows.select { |row| row[:genre].blank? || row[:genre] == "미분류" }
inference = Books::GenreInference.new(rows)

targets.each do |row|
  if row[:selection_type].to_s.split(";").include?("project_curated")
    genre = "문학"
    confidence = 0.95
    basis = "project_curated_peer_group"
    neighbors = []
  else
    result = inference.infer(row)
    genre = result.genre
    confidence = result.confidence
    basis = "weighted_similar_books"
    neighbors = result.neighbors.map(&:first)
  end

  row[:genre] = genre
  if row[:content_type].blank? || row[:content_type] == "미분류"
    row[:content_type] = genre == "문학" ? "문학" : "비문학"
  end
  if genre == "문학" && row[:monster_element] == "knowledge" && row[:topic_tags].blank?
    row[:monster_element] = "story"
  end
  row[:classification_confidence] = confidence < 0.72 ? "낮음" : "중간"
  row[:review_needed] = "예"

  notes = row[:notes].to_s.split(";").reject(&:blank?)
  notes.delete("KDC미분류")
  notes << "KDC없음·장르유사도서추정"
  notes << "장르추정근거=#{basis}"
  notes << "장르추정신뢰=#{confidence.round(2)}"
  notes << "유사책=#{neighbors.join(' / ')}" if neighbors.any?
  row[:notes] = notes.uniq.join(";")
end

tempfile = Tempfile.new([ "elementary_books", ".tsv" ], path.dirname)
begin
  CSV.open(tempfile.path, "w", col_sep: "\t", row_sep: "\n", encoding: "UTF-8") do |tsv|
    tsv << table.headers
    rows.each { |row| tsv << table.headers.map { |header| row[header.to_sym] } }
  end
  tempfile.close
  File.rename(tempfile.path, path)
ensure
  tempfile.close unless tempfile.closed?
  tempfile.unlink if File.exist?(tempfile.path)
end

puts "Filled #{targets.size} missing genres in #{path}"
