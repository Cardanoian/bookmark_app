# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# 자체 호스팅 폰트(Pretendard). app/assets/fonts 를 load path 에 추가해
# @font-face 의 url("pretendard/…woff2") 를 Propshaft 가 다이제스트 처리하게 한다.
Rails.application.config.assets.paths << Rails.root.join("app/assets/fonts")
