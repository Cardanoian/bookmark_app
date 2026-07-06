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

ActiveRecord::Schema[8.1].define(version: 2026_07_06_000004) do
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

  add_foreign_key "classrooms", "schools"
  add_foreign_key "classrooms", "users", column: "teacher_id"
  add_foreign_key "users", "classrooms"
  add_foreign_key "users", "schools"
end
