# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_20_000005) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.json "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "badges", force: :cascade do |t|
    t.string "condition_desc"
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "key"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_badges_on_key", unique: true
  end

  create_table "board_posts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "hidden", default: false, null: false
    t.integer "hidden_by_id"
    t.integer "report_id", null: false
    t.datetime "updated_at", null: false
    t.index ["hidden_by_id"], name: "index_board_posts_on_hidden_by_id"
    t.index ["report_id"], name: "index_board_posts_on_report_id", unique: true
  end

  create_table "book_intro_votes", force: :cascade do |t|
    t.integer "book_intro_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_intro_id", "user_id"], name: "index_book_intro_votes_on_book_intro_id_and_user_id", unique: true
    t.index ["book_intro_id"], name: "index_book_intro_votes_on_book_intro_id"
    t.index ["user_id"], name: "index_book_intro_votes_on_user_id"
  end

  create_table "book_intros", force: :cascade do |t|
    t.text "body", null: false
    t.integer "book_id", null: false
    t.integer "classroom_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "votes_count", default: 0, null: false
    t.index ["book_id", "classroom_id"], name: "index_book_intros_on_book_id_and_classroom_id"
    t.index ["book_id"], name: "index_book_intros_on_book_id"
    t.index ["classroom_id"], name: "index_book_intros_on_classroom_id"
    t.index ["user_id"], name: "index_book_intros_on_user_id"
  end

  create_table "book_recommendations", force: :cascade do |t|
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.string "issue"
    t.integer "position", null: false
    t.date "published_on"
    t.integer "recommendation_import_id", null: false
    t.string "section", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_book_recommendations_on_book_id"
    t.index ["recommendation_import_id", "book_id"], name: "index_book_recommendations_import_book", unique: true
    t.index ["recommendation_import_id", "position"], name: "index_book_recommendations_import_position"
    t.index ["recommendation_import_id"], name: "index_book_recommendations_on_recommendation_import_id"
  end

  create_table "book_sequel_votes", force: :cascade do |t|
    t.integer "book_sequel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_sequel_id", "user_id"], name: "index_book_sequel_votes_on_book_sequel_id_and_user_id", unique: true
    t.index ["book_sequel_id"], name: "index_book_sequel_votes_on_book_sequel_id"
    t.index ["user_id"], name: "index_book_sequel_votes_on_user_id"
  end

  create_table "book_sequels", force: :cascade do |t|
    t.text "ai_comment"
    t.integer "ai_status", default: 0, null: false
    t.text "body", null: false
    t.integer "book_id", null: false
    t.integer "classroom_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "votes_count", default: 0, null: false
    t.index ["book_id", "classroom_id"], name: "index_book_sequels_on_book_id_and_classroom_id"
    t.index ["book_id"], name: "index_book_sequels_on_book_id"
    t.index ["classroom_id"], name: "index_book_sequels_on_classroom_id"
    t.index ["user_id"], name: "index_book_sequels_on_user_id"
    t.index ["votes_count"], name: "index_book_sequels_on_votes_count"
  end

  create_table "books", force: :cascade do |t|
    t.string "author"
    t.integer "category", default: 0, null: false
    t.string "cover_url"
    t.datetime "created_at", null: false
    t.string "genre"
    t.string "grade_band"
    t.string "isbn", null: false
    t.string "publisher"
    t.text "summary"
    t.datetime "summary_checked_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "volume"
    t.index ["isbn"], name: "index_books_on_isbn", unique: true
    t.index ["title"], name: "index_books_on_title"
    t.check_constraint "length(isbn) = 13 AND isbn NOT GLOB '*[^0-9]*'", name: "chk_books_isbn13_format"
  end

  create_table "challenges", force: :cascade do |t|
    t.integer "book_id"
    t.datetime "created_at", null: false
    t.date "ends_on"
    t.integer "school_id"
    t.integer "scope", default: 0
    t.date "starts_on"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["school_id"], name: "index_challenges_on_school_id"
  end

  create_table "cheers", force: :cascade do |t|
    t.integer "board_post_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["board_post_id", "user_id"], name: "index_cheers_on_board_post_id_and_user_id", unique: true
    t.index ["board_post_id"], name: "index_cheers_on_board_post_id"
    t.index ["user_id"], name: "index_cheers_on_user_id"
  end

  create_table "classrooms", force: :cascade do |t|
    t.integer "class_no"
    t.datetime "created_at", null: false
    t.integer "grade"
    t.json "rubric_config"
    t.integer "school_id", null: false
    t.integer "teacher_id"
    t.datetime "updated_at", null: false
    t.index ["school_id", "grade", "class_no"], name: "index_classrooms_on_school_id_and_grade_and_class_no", unique: true
    t.index ["school_id"], name: "index_classrooms_on_school_id"
    t.index ["teacher_id"], name: "index_classrooms_on_teacher_id"
  end

  create_table "forum_post_likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "forum_post_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["forum_post_id", "user_id"], name: "index_forum_post_likes_on_forum_post_id_and_user_id", unique: true
    t.index ["forum_post_id"], name: "index_forum_post_likes_on_forum_post_id"
    t.index ["user_id"], name: "index_forum_post_likes_on_user_id"
  end

  create_table "forum_post_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "forum_post_id", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["forum_post_id", "user_id"], name: "index_forum_post_reports_on_forum_post_id_and_user_id", unique: true
    t.index ["forum_post_id"], name: "index_forum_post_reports_on_forum_post_id"
    t.index ["user_id"], name: "index_forum_post_reports_on_user_id"
  end

  create_table "forum_posts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "hidden", default: false, null: false
    t.integer "hidden_by_id"
    t.integer "likes_count", default: 0, null: false
    t.integer "reports_count", default: 0, null: false
    t.text "text"
    t.integer "topic_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["hidden_by_id"], name: "index_forum_posts_on_hidden_by_id"
    t.index ["topic_id"], name: "index_forum_posts_on_topic_id"
    t.index ["user_id"], name: "index_forum_posts_on_user_id"
  end

  create_table "game_plays", force: :cascade do |t|
    t.integer "book_id"
    t.datetime "created_at", null: false
    t.integer "game_type", null: false
    t.date "played_on", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_id"], name: "index_game_plays_on_book_id"
    t.index ["user_id", "game_type", "book_id", "played_on"], name: "index_game_plays_daily_dedup_with_book", unique: true, where: "book_id IS NOT NULL"
    t.index ["user_id", "game_type", "played_on"], name: "index_game_plays_daily_dedup_without_book", unique: true, where: "book_id IS NULL"
    t.index ["user_id"], name: "index_game_plays_on_user_id"
  end

  create_table "library_events", force: :cascade do |t|
    t.integer "book_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "event_on"
    t.integer "school_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["school_id"], name: "index_library_events_on_school_id"
  end

  create_table "library_loans", force: :cascade do |t|
    t.string "book_title"
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "isbn"
    t.string "period"
    t.integer "school_id"
    t.integer "source", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["school_id", "book_title", "period"], name: "index_library_loans_on_school_id_and_book_title_and_period"
    t.index ["school_id"], name: "index_library_loans_on_school_id"
  end

  create_table "mission_goals", force: :cascade do |t|
    t.integer "book_id"
    t.datetime "created_at", null: false
    t.integer "goal_type", null: false
    t.integer "mission_id", null: false
    t.integer "position"
    t.integer "target_count", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_mission_goals_on_book_id"
    t.index ["mission_id", "goal_type"], name: "index_mission_goals_on_mission_id_and_goal_type", unique: true
    t.index ["mission_id"], name: "index_mission_goals_on_mission_id"
    t.check_constraint "target_count > 0", name: "chk_mission_goals_target_count_positive"
  end

  create_table "mission_participations", force: :cascade do |t|
    t.datetime "assigned_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "mission_id", null: false
    t.integer "reward_points_awarded", default: 0, null: false
    t.datetime "rewarded_at"
    t.datetime "unassigned_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["mission_id", "user_id"], name: "index_mission_participations_on_mission_id_and_user_id", unique: true
    t.index ["mission_id"], name: "index_mission_participations_on_mission_id"
    t.index ["user_id", "completed_at"], name: "index_mission_participations_on_user_id_and_completed_at"
    t.index ["user_id"], name: "index_mission_participations_on_user_id"
    t.check_constraint "reward_points_awarded >= 0", name: "chk_mission_participations_reward_nonneg"
  end

  create_table "missions", force: :cascade do |t|
    t.datetime "cancelled_at"
    t.integer "classroom_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.date "end_date"
    t.datetime "published_at"
    t.integer "reward_points", default: 0, null: false
    t.date "start_date"
    t.integer "status", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["classroom_id", "status", "start_date"], name: "index_missions_on_classroom_id_and_status_and_start_date"
    t.index ["classroom_id"], name: "index_missions_on_classroom_id"
    t.index ["created_by_id"], name: "index_missions_on_created_by_id"
  end

  create_table "monster_species", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "dex_no"
    t.integer "element", default: 0
    t.json "evolve_condition"
    t.integer "evolves_from_id"
    t.string "image_key"
    t.string "key"
    t.string "name"
    t.integer "rarity", default: 0
    t.integer "stage"
    t.json "unlock_condition"
    t.datetime "updated_at", null: false
    t.index ["dex_no"], name: "index_monster_species_on_dex_no"
    t.index ["evolves_from_id"], name: "index_monster_species_on_evolves_from_id"
    t.index ["key"], name: "index_monster_species_on_key", unique: true
  end

  create_table "quiz_attempts", force: :cascade do |t|
    t.json "answers"
    t.datetime "created_at", null: false
    t.json "hint_reveals", default: {}, null: false
    t.datetime "played_at"
    t.integer "points_awarded", default: 0, null: false
    t.integer "quiz_id", null: false
    t.integer "score"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["quiz_id"], name: "index_quiz_attempts_on_quiz_id"
    t.index ["user_id"], name: "index_quiz_attempts_on_user_id"
  end

  create_table "quiz_contributions", force: :cascade do |t|
    t.integer "band", default: 0, null: false
    t.integer "book_id", null: false
    t.integer "classroom_id", null: false
    t.integer "content_axis", default: 0, null: false
    t.datetime "created_at", null: false
    t.json "payload"
    t.integer "reviewed_by_id"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_id"], name: "index_quiz_contributions_on_book_id"
    t.index ["classroom_id", "status"], name: "index_quiz_contributions_on_classroom_id_and_status"
    t.index ["classroom_id"], name: "index_quiz_contributions_on_classroom_id"
    t.index ["reviewed_by_id"], name: "index_quiz_contributions_on_reviewed_by_id"
    t.index ["user_id"], name: "index_quiz_contributions_on_user_id"
  end

  create_table "quiz_questions", force: :cascade do |t|
    t.json "answer"
    t.integer "answer_index"
    t.json "choices"
    t.json "content"
    t.datetime "created_at", null: false
    t.integer "difficulty"
    t.text "explanation"
    t.integer "position"
    t.text "prompt"
    t.integer "question_type", default: 0, null: false
    t.integer "quiz_id", null: false
    t.integer "source", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["quiz_id"], name: "index_quiz_questions_on_quiz_id"
  end

  create_table "quiz_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "quiz_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["quiz_id", "user_id"], name: "index_quiz_reports_on_quiz_id_and_user_id", unique: true
    t.index ["quiz_id"], name: "index_quiz_reports_on_quiz_id"
    t.index ["user_id"], name: "index_quiz_reports_on_user_id"
  end

  create_table "quizzes", force: :cascade do |t|
    t.integer "band"
    t.integer "book_id"
    t.integer "classroom_id"
    t.integer "content_axis"
    t.integer "content_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.integer "generation_status", default: 0, null: false
    t.integer "origin", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.boolean "reported", default: false, null: false
    t.integer "reports_count", default: 0, null: false
    t.integer "scope", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["book_id", "band", "content_axis", "content_version"], name: "index_quizzes_on_content_axis_dedup", unique: true, where: "origin = 1"
    t.index ["book_id", "band", "content_axis", "origin"], name: "index_quizzes_on_content_axis_delta"
    t.index ["book_id"], name: "index_quizzes_on_book_id"
    t.index ["classroom_id"], name: "index_quizzes_on_classroom_id"
    t.index ["created_by_id"], name: "index_quizzes_on_created_by_id"
  end

  create_table "recommendation_imports", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.string "file_digest", null: false
    t.string "filename", null: false
    t.datetime "imported_at", null: false
    t.integer "imported_by_id"
    t.integer "item_count", default: 0, null: false
    t.string "source_title"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_recommendation_imports_one_active", unique: true, where: "active = 1"
    t.index ["file_digest"], name: "index_recommendation_imports_on_file_digest", unique: true
    t.index ["imported_by_id"], name: "index_recommendation_imports_on_imported_by_id"
  end

  create_table "reports", force: :cascade do |t|
    t.integer "ai_status", default: 0, null: false
    t.float "avg"
    t.text "body"
    t.integer "book_id"
    t.string "book_title"
    t.integer "challenge_id"
    t.integer "cheers_count", default: 0, null: false
    t.integer "classroom_id", null: false
    t.datetime "created_at", null: false
    t.float "improvement"
    t.integer "input_mode", default: 0, null: false
    t.string "level", limit: 1
    t.integer "points_awarded", default: 0, null: false
    t.float "prev_avg"
    t.boolean "reviewed", default: false, null: false
    t.datetime "reviewed_at"
    t.integer "revision_of_id"
    t.json "rubric"
    t.boolean "shared", default: false, null: false
    t.float "similarity"
    t.text "teacher_comment"
    t.json "teacher_rubric"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_id"], name: "index_reports_on_book_id"
    t.index ["challenge_id"], name: "index_reports_on_challenge_id"
    t.index ["classroom_id", "reviewed"], name: "index_reports_on_classroom_id_and_reviewed"
    t.index ["classroom_id"], name: "index_reports_on_classroom_id"
    t.index ["level"], name: "index_reports_on_level"
    t.index ["reviewed"], name: "index_reports_on_reviewed"
    t.index ["revision_of_id"], name: "index_reports_on_revision_of_id"
    t.index ["user_id", "created_at"], name: "index_reports_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "schools", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.datetime "created_at", null: false
    t.string "data_source", default: "manual", null: false
    t.string "gu"
    t.string "name"
    t.string "neis_code"
    t.string "office_code"
    t.string "region"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["active", "region", "gu"], name: "index_schools_on_active_region_gu"
    t.index ["data_source"], name: "index_schools_on_data_source"
    t.index ["name"], name: "index_schools_on_name"
    t.index ["neis_code"], name: "index_schools_on_neis_code", unique: true
  end

  create_table "seasons", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "ends_on"
    t.string "name"
    t.integer "school_id"
    t.integer "scope", default: 0
    t.datetime "updated_at", null: false
  end

  create_table "stickers", force: :cascade do |t|
    t.integer "by_user_id", null: false
    t.datetime "created_at", null: false
    t.string "emoji"
    t.string "label"
    t.integer "position"
    t.integer "report_id", null: false
    t.datetime "updated_at", null: false
    t.index ["by_user_id"], name: "index_stickers_on_by_user_id"
    t.index ["report_id"], name: "index_stickers_on_report_id"
  end

  create_table "topics", force: :cascade do |t|
    t.integer "book_id"
    t.integer "classroom_id"
    t.datetime "created_at", null: false
    t.integer "forum_posts_count", default: 0, null: false
    t.boolean "hidden", default: false, null: false
    t.integer "hidden_by_id"
    t.integer "school_id"
    t.integer "scope", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["classroom_id"], name: "index_topics_on_classroom_id"
    t.index ["hidden_by_id"], name: "index_topics_on_hidden_by_id"
    t.index ["school_id"], name: "index_topics_on_school_id"
  end

  create_table "user_badges", force: :cascade do |t|
    t.integer "badge_id", null: false
    t.datetime "created_at", null: false
    t.datetime "earned_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["badge_id"], name: "index_user_badges_on_badge_id"
    t.index ["user_id", "badge_id"], name: "index_user_badges_on_user_id_and_badge_id", unique: true
    t.index ["user_id"], name: "index_user_badges_on_user_id"
  end

  create_table "user_monsters", force: :cascade do |t|
    t.datetime "celebrated_at"
    t.datetime "created_at", null: false
    t.integer "dex_no"
    t.datetime "evolved_at"
    t.integer "monster_species_id", null: false
    t.string "nickname"
    t.datetime "obtained_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["dex_no"], name: "index_user_monsters_on_dex_no"
    t.index ["monster_species_id"], name: "index_user_monsters_on_monster_species_id"
    t.index ["user_id", "dex_no"], name: "index_user_monsters_on_user_id_and_dex_no", unique: true
    t.index ["user_id"], name: "index_user_monsters_on_user_id"
    t.index ["user_id"], name: "index_user_monsters_pending_discovery", where: "celebrated_at IS NULL"
  end

  create_table "users", force: :cascade do |t|
    t.integer "active_monster_id"
    t.integer "classroom_id"
    t.datetime "created_at", null: false
    t.string "email"
    t.integer "experience", default: 0, null: false
    t.integer "mode", default: 0, null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.integer "points", default: 0, null: false
    t.integer "role", default: 0, null: false
    t.integer "school_id"
    t.boolean "suspended", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["classroom_id", "role", "points"], name: "index_users_on_classroom_role_points"
    t.index ["classroom_id"], name: "index_users_on_classroom_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["school_id", "classroom_id", "name"], name: "index_users_on_tuple_identity", unique: true
    t.index ["school_id", "role", "points"], name: "index_users_on_school_role_points"
    t.index ["school_id"], name: "index_users_on_school_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "board_posts", "reports"
  add_foreign_key "board_posts", "users", column: "hidden_by_id"
  add_foreign_key "book_intro_votes", "book_intros"
  add_foreign_key "book_intro_votes", "users"
  add_foreign_key "book_intros", "books"
  add_foreign_key "book_intros", "classrooms"
  add_foreign_key "book_intros", "users"
  add_foreign_key "book_recommendations", "books", on_delete: :cascade
  add_foreign_key "book_recommendations", "recommendation_imports", on_delete: :cascade
  add_foreign_key "book_sequel_votes", "book_sequels"
  add_foreign_key "book_sequel_votes", "users"
  add_foreign_key "book_sequels", "books"
  add_foreign_key "book_sequels", "classrooms"
  add_foreign_key "book_sequels", "users"
  add_foreign_key "challenges", "books", on_delete: :nullify
  add_foreign_key "challenges", "schools", on_delete: :nullify
  add_foreign_key "cheers", "board_posts"
  add_foreign_key "cheers", "users"
  add_foreign_key "classrooms", "schools"
  add_foreign_key "classrooms", "users", column: "teacher_id"
  add_foreign_key "forum_post_likes", "forum_posts"
  add_foreign_key "forum_post_likes", "users"
  add_foreign_key "forum_post_reports", "forum_posts"
  add_foreign_key "forum_post_reports", "users"
  add_foreign_key "forum_posts", "topics"
  add_foreign_key "forum_posts", "users"
  add_foreign_key "game_plays", "books"
  add_foreign_key "game_plays", "users"
  add_foreign_key "library_events", "books", on_delete: :nullify
  add_foreign_key "library_events", "schools", on_delete: :nullify
  add_foreign_key "library_loans", "schools", on_delete: :nullify
  add_foreign_key "mission_goals", "books", on_delete: :nullify
  add_foreign_key "mission_goals", "missions"
  add_foreign_key "mission_participations", "missions"
  add_foreign_key "mission_participations", "users"
  add_foreign_key "missions", "classrooms"
  add_foreign_key "missions", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "monster_species", "monster_species", column: "evolves_from_id", on_delete: :nullify
  add_foreign_key "quiz_attempts", "quizzes"
  add_foreign_key "quiz_attempts", "users"
  add_foreign_key "quiz_contributions", "books", on_delete: :cascade
  add_foreign_key "quiz_contributions", "classrooms", on_delete: :cascade
  add_foreign_key "quiz_contributions", "users", column: "reviewed_by_id", on_delete: :nullify
  add_foreign_key "quiz_contributions", "users", on_delete: :cascade
  add_foreign_key "quiz_questions", "quizzes"
  add_foreign_key "quiz_reports", "quizzes"
  add_foreign_key "quiz_reports", "users"
  add_foreign_key "quizzes", "books", on_delete: :nullify
  add_foreign_key "quizzes", "classrooms", on_delete: :nullify
  add_foreign_key "quizzes", "users", column: "created_by_id"
  add_foreign_key "recommendation_imports", "users", column: "imported_by_id", on_delete: :nullify
  add_foreign_key "reports", "books", on_delete: :nullify
  add_foreign_key "reports", "challenges"
  add_foreign_key "reports", "classrooms"
  add_foreign_key "reports", "reports", column: "revision_of_id"
  add_foreign_key "reports", "users"
  add_foreign_key "seasons", "schools", on_delete: :nullify
  add_foreign_key "stickers", "reports"
  add_foreign_key "stickers", "users", column: "by_user_id"
  add_foreign_key "topics", "books", on_delete: :nullify
  add_foreign_key "topics", "classrooms", on_delete: :nullify
  add_foreign_key "topics", "schools", on_delete: :nullify
  add_foreign_key "user_badges", "badges"
  add_foreign_key "user_badges", "users"
  add_foreign_key "user_monsters", "monster_species"
  add_foreign_key "user_monsters", "users"
  add_foreign_key "users", "classrooms"
  add_foreign_key "users", "schools"
  add_foreign_key "users", "user_monsters", column: "active_monster_id"
end
