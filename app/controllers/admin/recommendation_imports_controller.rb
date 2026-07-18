class Admin::RecommendationImportsController < Admin::BaseController
  MAX_HISTORY = 20

  def index
    @current_import = RecommendationImport.current
    @imports = RecommendationImport.includes(:imported_by).order(imported_at: :desc).limit(MAX_HISTORY)
    @recommendations = @current_import&.book_recommendations&.includes(:book)&.order(:position)&.limit(50) || []
  end

  def create
    upload = params[:file]
    unless upload.respond_to?(:tempfile)
      redirect_to admin_recommendation_imports_path, alert: "업로드할 XLSX 파일을 선택해 주세요."
      return
    end

    result = Recommendations::Importer.new(
      path: upload.tempfile.path,
      filename: upload.original_filename
    ).call(imported_by: Current.user)

    message = if result.reused
      "이미 처리한 파일입니다. 해당 추천도서 #{result.recommendation_import.item_count}권을 다시 활성화했어요."
    else
      "추천도서 #{result.recommendation_import.item_count}권을 업데이트했어요."
    end
    redirect_to admin_recommendation_imports_path, notice: message
  rescue Recommendations::Importer::Error => error
    redirect_to admin_recommendation_imports_path, alert: error.message
  end
end
