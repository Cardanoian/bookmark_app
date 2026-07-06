# 전역 케어/진화 상점 아이템 CRUD(P7.3). effect 는 JSON 텍스트에어리어로 편집.
class Admin::ShopItemsController < Admin::BaseController
  before_action :set_shop_item, only: [ :show, :edit, :update, :destroy ]

  def index
    @shop_items = ShopItem.order(:category, :name)
  end

  def show
  end

  def new
    @shop_item = ShopItem.new
  end

  def create
    @shop_item = ShopItem.new(shop_item_params)
    apply_effect_json(@shop_item)

    if @effect_error.nil? && @shop_item.save
      redirect_to admin_shop_item_path(@shop_item), notice: "‘#{@shop_item.name}’ 아이템을 등록했어요."
    else
      flash.now[:alert] = @effect_error if @effect_error
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @shop_item.assign_attributes(shop_item_params)
    apply_effect_json(@shop_item)

    if @effect_error.nil? && @shop_item.save
      redirect_to admin_shop_item_path(@shop_item), notice: "아이템을 수정했어요."
    else
      flash.now[:alert] = @effect_error if @effect_error
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @shop_item.destroy
    redirect_to admin_shop_items_path, notice: "아이템을 삭제했어요."
  end

  private

  def set_shop_item
    @shop_item = ShopItem.find(params[:id])
  end

  # effect JSON 텍스트를 안전하게 파싱한다. 잘못된 JSON 은 크래시 대신 오류 메시지.
  def apply_effect_json(item)
    raw = params.dig(:shop_item, :effect_json)
    return if raw.nil?

    stripped = raw.to_s.strip
    item.effect = stripped.blank? ? nil : JSON.parse(stripped)
  rescue JSON::ParserError
    @effect_error = "효과(effect)는 올바른 JSON 형식이어야 합니다."
  end

  def shop_item_params
    params.require(:shop_item).permit(:name, :category, :cost, :consumable, :icon, :image_key)
  end
end
