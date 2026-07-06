# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# "monster_species" 는 단수·복수가 같다(species 는 불가산). 기본 인플렉터는
# "monster_specy" 로 잘못 단수화하므로 관리자 라우트 헬퍼가 자연스럽도록 불가산 처리한다.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.uncountable %w[monster_species]
end
