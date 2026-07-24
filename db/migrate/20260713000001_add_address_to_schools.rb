# 학교 도로명주소(NEIS ORG_RDNMA) 원본 저장 컬럼(OQ3). 전량 시드가 시군구(gu)를
# 파싱하는 원본을 함께 보관해 gu 파싱 검증·향후 학교 검색 UX 에 쓴다. 위경도는 유예
# (지도 기능 착수 시 별도 소스로 추가). 기존 축소 시드 17교는 address 가 nil 로 남는다.
class AddAddressToSchools < ActiveRecord::Migration[8.1]
  def change
    add_column :schools, :address, :string
  end
end
