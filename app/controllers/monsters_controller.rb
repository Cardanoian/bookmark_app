# 몬스터 도감·진화·발견 연출(P4.5/P4.7). 라인(dex_no) 단위로 조회하며 제자리 진화한다.
class MonstersController < ApplicationController
  before_action :set_user_monster, only: [ :evolve, :set_active ]

  # 도감: 시드된 12 라인 그리드 + 완성도(분모 24 고정).
  def index
    authorize :monster, :index?
    # 조회 시 self-heal: 해금 조건은 충족했으나 쓰기 트리거(승인·게임·토론 등)를 거치지 않아
    # 고착된 라인을 도감을 여는 순간 재평가해 해금한다(트리거 커버리지 갭 보정). 신규 발견은
    # 레이아웃의 pending_celebration 드레인이 같은 렌더에서 축하 모달로 표면화한다.
    evaluate_monster_unlocks(current_user)
    @lines = MonsterSpecies.where(stage: 1).order(:dex_no).to_a
    @owned = current_user.user_monsters.includes(:monster_species).index_by(&:dex_no)
    @evolvable_ids = current_user.evolvable_monsters.map(&:id).to_set
    @dex_count = current_user.user_monsters.distinct.count(:dex_no)
    @design_lines = MonsterSpecies::DESIGN_LINE_COUNT
    # 잠긴 카드에 해금 조건 진행도(예: "승인 독후감 4/6편")를 그리기 위한 지표 스냅샷.
    @stats = ReadingStats.new(current_user)
  end

  # 상세: 종·단계·진화 조건 진행률(ReadingStats 대비)·케어 상태.
  def show
    authorize :monster, :show?
    # 조회 시 self-heal(index 와 동일): 이 상세를 열 때 조건 충족·미해금 라인을 재평가해,
    # 아래 @user_monster 조회가 방금 해금된 개체를 집어 즉시 "보유"로 렌더되게 한다.
    evaluate_monster_unlocks(current_user)
    @dex_no = params[:id].to_i
    @line = MonsterSpecies.where(dex_no: @dex_no).order(:stage).to_a
    raise ActiveRecord::RecordNotFound, "unknown dex_no #{@dex_no}" if @line.empty?

    @user_monster = current_user.user_monsters.find_by(dex_no: @dex_no)
    @current_species = @user_monster&.monster_species || @line.first
    @stats = ReadingStats.new(current_user)
    @evolvable = @user_monster&.evolvable? || false
    # AI 첨삭은 끝났지만(done) 아직 교사 승인 전(reviewed: false)이라 진화 조건 '독후감 수'
    # (ReadingStats#reports = 승인 독후감)에 아직 안 잡힌 글 수. 조건에 reports 키가 있을 때
    # "승인되면 반영된다"는 안내를 띄워 첨삭 완료/승인 대기의 시점 차이를 학생에게 설명한다.
    @awaiting_review_count = current_user.reports.done.where(reviewed: false).count
  end

  # 스타터 선택(온보딩). 보유 0 인 학생만. 잘못/중복 선택 거부(가챠/랜덤 없음).
  def choose_starter
    authorize :monster, :choose_starter?
    if current_user.user_monsters.exists?
      return redirect_to monsters_path, alert: "이미 반려 몬스터를 보유하고 있어요."
    end

    monster = MonsterAcquisition.new(current_user).choose_starter!(params[:key])
    # 스타터 선택 직후 나머지 라인의 해금 조건도 재평가한다(md §4 스타터 선택 직후 평가 시점).
    discovered = evaluate_monster_unlocks(current_user)
    redirect_to monster_path(monster.dex_no),
                notice: with_discovery("#{monster.species.name}와(과) 함께 모험을 시작해요!", discovered)
  rescue MonsterAcquisition::InvalidStarter, MonsterAcquisition::AlreadyOwned
    redirect_to monsters_path, alert: "스타터를 선택할 수 없어요."
  end

  # 진화: 조건 충족 시 필요 포인트 차감 + 제자리 진화 + 헤더/상세 실시간 갱신.
  def evolve
    authorize @user_monster, :evolve?, policy_class: MonsterPolicy

    unless @user_monster.evolvable?
      return redirect_to monster_path(@user_monster.dex_no), alert: "아직 진화 조건을 충족하지 못했어요."
    end

    cost = @user_monster.evolution_cost
    form = current_user.evolve_monster!(@user_monster)
    unless form
      return redirect_to monster_path(@user_monster.dex_no), alert: "진화에 필요한 포인트가 부족해요."
    end

    current_user.reload.broadcast_ranking_change
    broadcast_active_monster if active?(@user_monster)
    flash[:celebrate] = "evolve"
    redirect_to monster_path(@user_monster.dex_no), notice: "#{cost}포인트를 사용해 #{form.name}(으)로 진화했어요! ✨"
  end

  # 대표(활성) 몬스터 지정.
  def set_active
    authorize @user_monster, :set_active?, policy_class: MonsterPolicy
    current_user.update!(active_monster: @user_monster)
    broadcast_active_monster
    redirect_to monster_path(@user_monster.dex_no), notice: "#{@user_monster.species.name}(을)를 대표 몬스터로 정했어요."
  end

  private

  def set_user_monster
    @user_monster = current_user.user_monsters.find_by(dex_no: params[:id])
  end

  def active?(monster)
    current_user.active_monster_id == monster.id
  end

  def broadcast_active_monster
    monster = current_user.active_monster
    return unless monster

    monster.broadcast_replace_to(
      [ current_user, :active_monster ],
      target: "active_monster",
      partial: "monsters/active_monster",
      locals: { monster: monster, user: current_user }
    )
  end
end
