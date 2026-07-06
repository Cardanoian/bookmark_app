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

ActiveRecord::Schema[8.1].define(version: 2026_07_06_140011) do
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

  create_table "badges", force: :cascade do |t|
    t.string "condition_desc"
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "key"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_badges_on_key", unique: true
  end

  create_table "books", force: :cascade do |t|
    t.string "author"
    t.integer "category", default: 0, null: false
    t.string "cover_url"
    t.datetime "created_at", null: false
    t.string "grade_band"
    t.string "isbn"
    t.string "publisher"
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["isbn"], name: "index_books_on_isbn"
    t.index ["title"], name: "index_books_on_title"
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

  create_table "missions", force: :cascade do |t|
    t.integer "book_id"
    t.integer "classroom_id", null: false
    t.datetime "created_at", null: false
    t.date "end_date"
    t.date "start_date"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_missions_on_book_id"
    t.index ["classroom_id"], name: "index_missions_on_classroom_id"
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
    t.datetime "updated_at", null: false
    t.index ["dex_no"], name: "index_monster_species_on_dex_no"
    t.index ["evolves_from_id"], name: "index_monster_species_on_evolves_from_id"
    t.index ["key"], name: "index_monster_species_on_key", unique: true
  end

  create_table "purchases", force: :cascade do |t|
    t.datetime "bought_at"
    t.datetime "created_at", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "shop_item_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["shop_item_id"], name: "index_purchases_on_shop_item_id"
    t.index ["user_id", "shop_item_id"], name: "index_purchases_on_user_id_and_shop_item_id", unique: true
    t.index ["user_id"], name: "index_purchases_on_user_id"
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
    t.integer "mission_id"
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
    t.index ["mission_id"], name: "index_reports_on_mission_id"
    t.index ["reviewed"], name: "index_reports_on_reviewed"
    t.index ["revision_of_id"], name: "index_reports_on_revision_of_id"
    t.index ["user_id", "created_at"], name: "index_reports_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "schools", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "gu"
    t.string "name"
    t.string "neis_code"
    t.string "office_code"
    t.string "region"
    t.datetime "updated_at", null: false
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

  create_table "shop_items", force: :cascade do |t|
    t.integer "category", default: 0
    t.boolean "consumable", default: false, null: false
    t.integer "cost", default: 0
    t.datetime "created_at", null: false
    t.json "effect"
    t.string "icon"
    t.string "image_key"
    t.string "name"
    t.datetime "updated_at", null: false
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
    t.json "care"
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
  end

  create_table "users", force: :cascade do |t|
    t.integer "active_monster_id"
    t.integer "classroom_id"
    t.datetime "created_at", null: false
    t.integer "mode", default: 0, null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.integer "points", default: 0, null: false
    t.integer "role", default: 0, null: false
    t.integer "school_id"
    t.boolean "suspended", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["classroom_id"], name: "index_users_on_classroom_id"
    t.index ["role"], name: "index_users_on_role"
    t.index ["school_id", "classroom_id", "name"], name: "index_users_on_tuple_identity", unique: true
    t.index ["school_id"], name: "index_users_on_school_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "classrooms", "schools"
  add_foreign_key "classrooms", "users", column: "teacher_id"
  add_foreign_key "missions", "classrooms"
  add_foreign_key "monster_species", "monster_species", column: "evolves_from_id"
  add_foreign_key "purchases", "shop_items"
  add_foreign_key "purchases", "users"
  add_foreign_key "reports", "books"
  add_foreign_key "reports", "challenges"
  add_foreign_key "reports", "classrooms"
  add_foreign_key "reports", "missions"
  add_foreign_key "reports", "reports", column: "revision_of_id"
  add_foreign_key "reports", "users"
  add_foreign_key "user_badges", "badges"
  add_foreign_key "user_badges", "users"
  add_foreign_key "user_monsters", "monster_species", column: "monster_species_id"
  add_foreign_key "user_monsters", "users"
  add_foreign_key "users", "classrooms"
  add_foreign_key "users", "schools"
  add_foreign_key "users", "user_monsters", column: "active_monster_id"
end
