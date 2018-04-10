# frozen_string_literal: true

begin
  require "bundler/inline"
rescue LoadError => e
  $stderr.puts "Bundler version 1.10 or later is required. Please update your Bundler"
  raise e
end

adapter = ARGV[0]

if adapter.nil? or !['pg', 'sqlite3'].include?(adapter)
  raise "\n\n-------------------\nPass the argument for the adapter: sqlite3 | pg  \nIf pg you should start the db with 'docker-compose up' in a new terminal"
end

gemfile(true) do
  source "https://rubygems.org"

  git_source(:github) {|repo| "https://github.com/#{repo}.git"}

  # Activate the gem you are reporting the issue against.
  gem "activerecord", "5.2.0"
  if adapter == 'pg'
    gem "pg"
  end

  if adapter == 'sqlite3'
    gem 'sqlite3'
  end

end

require "active_record"
require "minitest/autorun"
require "logger"

# Ensure backward compatibility with Minitest 4
Minitest::Test = MiniTest::Unit::TestCase unless defined?(Minitest::Test)


if adapter == 'pg'
# This connection will do for database-independent bug reports.
  ActiveRecord::Base.establish_connection(
    adapter: 'postgresql',
    encoding: 'utf8',
    pool: 5,
    username: ENV.fetch("POSTGRES_USER") {%x( docker-compose run --rm db env | grep POSTGRES_USER ).match("=(.*)")[1].strip},
    password: ENV.fetch("POSTGRES_USER") {%x( docker-compose run --rm db env | grep POSTGRES_USER ).match("=(.*)")[1].strip},
    host: ENV.fetch("POSTGRES_HOST") {%x( docker-compose port db 5432).match("(.*):")[1]},
    port: ENV.fetch("POSTGRES_PORT") {%x( docker-compose port db 5432).match(":([0-9]+)")[1]},
    database: ENV.fetch("POSTGRES_DB") {%x( docker-compose run --rm db env | grep POSTGRES_DB ).match("=(.*)")[1].strip}
  )
end

if adapter == 'sqlite3'
# This connection will do for database-independent bug reports.
  ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
end


ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do


  drop_table "pages",if_exists:true
  drop_table "elements",if_exists:true
  drop_table "contents",if_exists:true
  drop_table "essence_texts",if_exists:true

  create_table "pages" do |t|
  end

  create_table "elements" do |t|
    t.integer "page_id", null: false
    t.integer "parent_element_id"
    t.integer "position"
    t.boolean "public", default: true
  end

  create_table "contents" do |t|
    t.string "essence_type", null: false
    t.integer "essence_id", null: false
    t.integer "element_id", null: false
  end

  create_table "essence_texts" do |t|
    t.boolean "searchable", default: true
  end


end

class Page < ActiveRecord::Base

  has_many :elements, -> {where(parent_element_id: nil)}

  has_many :descendent_elements,
           -> {order(:position).not_trashed},
           class_name: 'Element'

  has_many :descendent_contents,
           through: :descendent_elements,
           class_name: 'Content',
           source: :contents


  has_many :searchable_essence_texts,
           -> {where(essence_texts: {searchable: true}, elements: {public: true})},
           class_name: 'EssenceText',
           source_type: 'EssenceText',
           through: :descendent_contents,
           source: :essence
end

class Element < ActiveRecord::Base
  belongs_to :page, required: true
  has_many :contents, -> {order(:position, :id)}, dependent: :destroy

  scope :not_trashed, -> {where(Element.arel_table[:position].not_eq(nil))}
end

class Content < ActiveRecord::Base
  belongs_to :essence, required: false, polymorphic: true, dependent: :destroy

  belongs_to :element, required: false, touch: true

  has_one :page, through: :element

  scope :not_trashed, -> {joins(:element).merge(Element.not_trashed)}
end

class EssenceText < ActiveRecord::Base
  has_one :content, :as => :essence, class_name: "Content"
  has_one :element, :through => :content, class_name: "Element"
  has_one :page, :through => :element, class_name: "Page"
end

class BugTest < Minitest::Test
  def test_association_stuff
    page = Page.create!
    element = Element.create!(page: page, position: 1, parent_element_id: nil)

    essence = EssenceText.create!(searchable: true)

    content = Content.create!(element: element, essence: essence)


    assert_equal 1, Page.count
    assert_equal 1, Element.count
    assert_equal 1, page.elements.count

    assert_equal 1, page.searchable_essence_texts.count
    assert_equal 1, Page.joins(:searchable_essence_texts).count


  end
end