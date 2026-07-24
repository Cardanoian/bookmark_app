module ApplicationHelper
  UI_ICON_NAMES = %i[
    arrow_left arrow_right book_open book_cover books camera celebrate chart check cheer chevron_down close crown detective dice
    discussion document download egg eye flag flame game gift graduation heart home inbox
    info lightbulb like link location lock medal medal_bronze medal_gold medal_silver megaphone
    menu mystery paw quiz refresh save school search smile sparkle star student students target teacher
    trophy warning writing
  ].freeze

  STICKER_ICONS = {
    "👍" => :like,
    "👏" => :cheer,
    "🌟" => :star,
    "❤️" => :heart,
    "😊" => :smile
  }.freeze

  STICKER_REACTIONS = [
    [ "👍", :like, "좋아요" ],
    [ "👏", :cheer, "응원" ],
    [ "🌟", :star, "반짝이어요" ],
    [ "❤️", :heart, "마음에 들어요" ],
    [ "😊", :smile, "기분이 좋아요" ]
  ].freeze

  EMPTY_STATE_IMAGES = {
    inbox: "empty_states/empty-inbox.png",
    books: "empty_states/empty-books.png",
    book_open: "empty_states/empty-reading.png",
    writing: "empty_states/sequel-writing.png",
    discussion: "empty_states/empty-discussion.png",
    chart: "empty_states/empty-stats.png",
    document: "empty_states/empty-review.png",
    target: "empty_states/empty-mission.png",
    flame: "empty_states/empty-challenge.png",
    quiz: "empty_states/empty-quiz.png",
    link: "empty_states/empty-account-link.png",
    school: "empty_states/empty-ranking.png",
    graduation: "empty_states/empty-ranking.png",
    crown: "empty_states/empty-ranking.png",
    medal: "empty_states/empty-award.png"
  }.freeze

  # 이모지 대신 프로젝트 공용 SVG 스프라이트의 symbol 을 렌더한다.
  # 대부분은 인접한 텍스트 라벨을 보조하는 장식용이라 aria-hidden 이 기본이다.
  def ui_icon(name, label: nil, class_name: "h-5 w-5", **html_options)
    icon_name = name.to_sym
    raise ArgumentError, "Unknown UI icon: #{name}" unless UI_ICON_NAMES.include?(icon_name)

    accessibility = if label.present?
      { role: "img", aria: { label: label } }
    else
      { aria: { hidden: "true" } }
    end

    options = {
      class: "inline-block shrink-0 align-[-0.125em] #{class_name}",
      focusable: "false"
    }.merge(accessibility).merge(html_options)

    content_tag(:svg, **options) do
      tag.use(href: "#{asset_path("ui-icons.svg")}##{icon_name.to_s.dasherize}")
    end
  end

  def icon_text(icon, text, icon_class: "h-4 w-4")
    safe_join([ ui_icon(icon, class_name: icon_class), content_tag(:span, text) ], " ")
  end

  def text_icon(text, icon, icon_class: "h-4 w-4")
    safe_join([ content_tag(:span, text), ui_icon(icon, class_name: icon_class) ], " ")
  end

  def sticker_icon(emoji, class_name: "h-4 w-4")
    ui_icon(STICKER_ICONS.fetch(emoji, :sparkle), class_name: class_name)
  end

  def sticker_reactions
    STICKER_REACTIONS
  end

  def empty_state_image(icon)
    EMPTY_STATE_IMAGES.fetch(icon.to_sym, EMPTY_STATE_IMAGES.fetch(:inbox))
  end
end
