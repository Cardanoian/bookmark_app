# 도서 카탈로그·검색 정책(P5.1/P5.2). 열람·검색은 로그인 사용자.
class BookPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def search?
    user.present?
  end
end
