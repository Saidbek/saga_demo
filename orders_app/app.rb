#!/usr/bin/env ruby
# frozen_string_literal: true

# Orders App - Saga Orchestrator
# Port: 4000

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
  gem "httparty"
  gem "rackup"
  gem "puma"
end

require "active_record"
require "action_controller/railtie"
require "httparty"
require "rackup"

# Database setup
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: File.join(__dir__, "orders.sqlite3")
)

ActiveRecord::Schema.define do
  create_table :orders, force: true do |t|
    t.string :status, default: "pending"
    t.timestamps
  end
end

# Model
class Order < ActiveRecord::Base
  validates :status, inclusion: { in: %w[pending paid reserved shipped failed] }
end

# HTTP Clients for other services
class PaymentClient
  include HTTParty
  base_uri "http://localhost:4001"

  def self.create_payment(order_id)
    response = post("/payments", body: { order_id: order_id })
    { success: response.code == 201, data: response.parsed_response }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def self.refund(order_id)
    response = post("/payments/refund", body: { order_id: order_id })
    { success: response.code == 200, data: response.parsed_response }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end

class InventoryClient
  include HTTParty
  base_uri "http://localhost:4002"

  def self.reserve(order_id)
    response = post("/inventory/reserve", body: { order_id: order_id })
    { success: response.code == 201, data: response.parsed_response }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def self.release(order_id)
    response = post("/inventory/release", body: { order_id: order_id })
    { success: response.code == 200, data: response.parsed_response }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end

class ShippingClient
  include HTTParty
  base_uri "http://localhost:4003"

  def self.create_shipment(order_id)
    response = post("/shipping/create", body: { order_id: order_id })
    { success: response.code == 201, data: response.parsed_response }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end

# Saga Orchestrator
class OrderSaga
  attr_reader :order, :steps_completed

  def initialize(order)
    @order = order
    @steps_completed = []
  end

  def execute
    # Step 1: Payment
    payment_result = PaymentClient.create_payment(order.id)
    unless payment_result[:success]
      compensate!
      return { success: false, step: "payment", error: payment_result }
    end
    @steps_completed << :payment
    order.update!(status: "paid")

    # Step 2: Inventory
    inventory_result = InventoryClient.reserve(order.id)
    unless inventory_result[:success]
      compensate!
      return { success: false, step: "inventory", error: inventory_result }
    end
    @steps_completed << :inventory
    order.update!(status: "reserved")

    # Step 3: Shipping
    shipping_result = ShippingClient.create_shipment(order.id)
    unless shipping_result[:success]
      compensate!
      return { success: false, step: "shipping", error: shipping_result }
    end
    @steps_completed << :shipping
    order.update!(status: "shipped")

    { success: true, order: order }
  end

  private

  def compensate!
    puts "[SAGA] Starting compensation for order #{order.id}..."
    puts "[SAGA] Steps completed: #{@steps_completed.inspect}"

    if @steps_completed.include?(:inventory)
      puts "[SAGA] Releasing inventory..."
      InventoryClient.release(order.id)
    end

    if @steps_completed.include?(:payment)
      puts "[SAGA] Refunding payment..."
      PaymentClient.refund(order.id)
    end

    order.update!(status: "failed")
    puts "[SAGA] Compensation complete. Order marked as failed."
  end
end

# Rails Application
class OrdersApp < Rails::Application
  config.api_only = true
  config.hosts.clear
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "orders_app_secret_key_base_for_demo"

  routes.append do
    resources :orders, only: [:create, :show, :index]
  end
end

class OrdersController < ActionController::API
  def index
    orders = Order.all.order(created_at: :desc)
    render json: orders
  end

  def show
    order = Order.find(params[:id])
    render json: order
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Order not found" }, status: :not_found
  end

  def create
    order = Order.create!(status: "pending")
    puts "\n" + "=" * 60
    puts "[ORDER #{order.id}] Created with status: pending"
    puts "[ORDER #{order.id}] Starting Saga execution..."
    puts "=" * 60

    saga = OrderSaga.new(order)
    result = saga.execute

    if result[:success]
      puts "[ORDER #{order.id}] ✅ Saga completed successfully!"
      puts "=" * 60 + "\n"
      render json: { order: order.reload, message: "Order completed successfully" }, status: :created
    else
      puts "[ORDER #{order.id}] ❌ Saga failed at step: #{result[:step]}"
      puts "=" * 60 + "\n"
      render json: {
        order: order.reload,
        message: "Order failed",
        failed_step: result[:step],
        error: result[:error]
      }, status: :unprocessable_entity
    end
  end
end

OrdersApp.initialize!

puts "\n" + "=" * 60
puts "🚀 ORDERS APP (Saga Orchestrator) starting on port 4000"
puts "=" * 60
puts "Endpoints:"
puts "  POST /orders     - Create new order and execute saga"
puts "  GET  /orders     - List all orders"
puts "  GET  /orders/:id - Show specific order"
puts "=" * 60 + "\n"

Rackup::Server.new(app: OrdersApp, Port: 4000, Host: "0.0.0.0").start

