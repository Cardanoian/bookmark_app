# frozen_string_literal: true

require "digest"
require "fileutils"

module DemoData
  # 운영 데이터 정비 직전의 primary SQLite 전체 백업. VACUUM INTO 로 한 파일에 떠서 0600 으로 두고
  # 크기·SHA-256 을 남긴다. 정비 서비스(공개 체험 재구성·토론 재구성)가 함께 쓴다.
  module DatabaseBackup
    BACKUP_DIR = Rails.root.join("storage/demo_backups")
    DATABASE_PATH = Rails.root.join("storage/production.sqlite3")

    module_function

    def call!(label:, io:, error_class:)
      connection = ApplicationRecord.connection
      raise error_class, "자동 백업은 SQLite에서만 지원합니다" unless connection.adapter_name == "SQLite"
      raise error_class, "운영 데이터베이스 파일을 찾을 수 없습니다" unless DATABASE_PATH.file?

      FileUtils.mkdir_p(BACKUP_DIR)
      timestamp = Time.current.utc.strftime("%Y%m%d%H%M%S")
      path = BACKUP_DIR.join("production-before-#{label}-#{timestamp}-#{Process.pid}.sqlite3")
      connection.execute("VACUUM INTO #{connection.quote(path.to_s)}")
      File.chmod(0o600, path)

      info = { path: path.to_s, bytes: path.size, sha256: Digest::SHA256.file(path).hexdigest }
      io.puts "  [demo-backup] #{info[:path]} (#{info[:bytes]} bytes, sha256=#{info[:sha256]})"
      info
    end
  end
end
