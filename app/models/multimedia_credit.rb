class MultimediaCredit
  DATA_PATH = Rails.root.join("config/multimedia_credits.json")

  def self.all
    if Rails.env.development?
      JSON.parse(File.read(DATA_PATH), symbolize_names: true)
    else
      @all ||= JSON.parse(File.read(DATA_PATH), symbolize_names: true)
    end
  end
end
