#!/usr/bin/env ruby
# frozen_string_literal: true

# Shipping App
# Port: 4003

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
  database: File.join(__dir__, "shipping.sqlite3")
)

ActiveRecord::Schema.define do
  create_table :shipments, force: true do |t|
    t.integer :order_id
    t.string :status, default: "shipped"
    t.timestamps
  end
end

# Model
class Shipment < ActiveRecord::Base
  validates :order_id, presence: true
  validates :status, inclusion: { in: %w[shipped] }
end

# Rails Application
class ShippingApp < Rails::Application
  config.api_only = true
  config.hosts.clear
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "shipping_app_secret_key_base_for_demo"

  routes.append do
    post "/shipping/create", to: "shipping#create"
    get "/shipping", to: "shipping#index"
  end
end

class ShippingController < ActionController::API
  # 70% chance of success
  FAILURE_RATE = 0.3

  def index
    shipments = Shipment.all.order(created_at: :desc)
    render json: shipments
  end

  def create
    order_id = params[:order_id]

    # Simulate random failure
    if rand < FAILURE_RATE
      puts "[SHIPPING] ❌ Shipment FAILED for order #{order_id} (simulated failure - carrier unavailable)"
      render json: { error: "Shipping carrier unavailable", order_id: order_id }, status: :service_unavailable
      return
    end

    shipment = Shipment.create!(order_id: order_id, status: "shipped")
    puts "[SHIPPING] ✅ Shipment CREATED for order #{order_id}"
    render json: shipment, status: :created
  end
end

ShippingApp.initialize!

puts "\n" + "=" * 60
puts "🚚 SHIPPING APP starting on port 4003"
puts "=" * 60
puts "Endpoints:"
puts "  POST /shipping/create - Create shipment (#{((1 - ShippingController::FAILURE_RATE) * 100).to_i}% success rate)"
puts "  GET  /shipping        - List all shipments"
puts "=" * 60 + "\n"

Rackup::Server.new(app: ShippingApp, Port: 4003, Host: "0.0.0.0").start

