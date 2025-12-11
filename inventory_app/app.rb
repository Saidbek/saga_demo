#!/usr/bin/env ruby
# frozen_string_literal: true

# Inventory App
# Port: 4002

begin
  require "bundler/inline"
rescue LoadError => e
  $stderr.puts "Bundler version 1.10 or later is required."
  raise e
end

gemfile(true) do
  source "https://rubygems.org"
  gem "rails", "~> 7.1.0"
  gem "sqlite3", "~> 1.6"
  gem "rackup"
  gem "puma"
end

require "active_record"
require "action_controller/railtie"
require "rackup"

# Database setup
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: File.join(__dir__, "inventory.sqlite3")
)

ActiveRecord::Schema.define do
  create_table :inventory_reservations, force: true do |t|
    t.integer :order_id
    t.string :status, default: "reserved"
    t.timestamps
  end
end

# Model
class InventoryReservation < ActiveRecord::Base
  validates :order_id, presence: true
  validates :status, inclusion: { in: %w[reserved released] }
end

# Rails Application
class InventoryApp < Rails::Application
  config.api_only = true
  config.hosts.clear
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "inventory_app_secret_key_base_for_demo"

  routes.append do
    post "/inventory/reserve", to: "inventory#reserve"
    post "/inventory/release", to: "inventory#release"
    get "/inventory", to: "inventory#index"
  end
end

class InventoryController < ActionController::API
  # 70% chance of success
  FAILURE_RATE = 0.3

  def index
    reservations = InventoryReservation.all.order(created_at: :desc)
    render json: reservations
  end

  def reserve
    order_id = params[:order_id]

    # Simulate random failure
    if rand < FAILURE_RATE
      puts "[INVENTORY] ❌ Reservation FAILED for order #{order_id} (simulated failure - out of stock)"
      render json: { error: "Out of stock", order_id: order_id }, status: :conflict
      return
    end

    reservation = InventoryReservation.create!(order_id: order_id, status: "reserved")
    puts "[INVENTORY] ✅ Inventory RESERVED for order #{order_id}"
    render json: reservation, status: :created
  end

  def release
    order_id = params[:order_id]
    reservation = InventoryReservation.find_by(order_id: order_id)

    if reservation
      reservation.update!(status: "released")
      puts "[INVENTORY] 📦 Inventory RELEASED for order #{order_id}"
      render json: reservation
    else
      puts "[INVENTORY] ⚠️ No reservation found to release for order #{order_id}"
      render json: { message: "No reservation found", order_id: order_id }
    end
  end
end

InventoryApp.initialize!

puts "\n" + "=" * 60
puts "📦 INVENTORY APP starting on port 4002"
puts "=" * 60
puts "Endpoints:"
puts "  POST /inventory/reserve - Reserve inventory (#{((1 - InventoryController::FAILURE_RATE) * 100).to_i}% success rate)"
puts "  POST /inventory/release - Release inventory (compensation)"
puts "  GET  /inventory         - List all reservations"
puts "=" * 60 + "\n"

Rackup::Server.new(app: InventoryApp, Port: 4002, Host: "0.0.0.0").start

