#!/usr/bin/env ruby
# frozen_string_literal: true

# Payments App
# Port: 4001

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
  database: File.join(__dir__, "payments.sqlite3")
)

ActiveRecord::Schema.define do
  create_table :payments, force: true do |t|
    t.integer :order_id
    t.string :status, default: "authorized"
    t.timestamps
  end
end

# Model
class Payment < ActiveRecord::Base
  validates :order_id, presence: true
  validates :status, inclusion: { in: %w[authorized refunded] }
end

# Rails Application
class PaymentsApp < Rails::Application
  config.api_only = true
  config.hosts.clear
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "payments_app_secret_key_base_for_demo"

  routes.append do
    post "/payments", to: "payments#create"
    post "/payments/refund", to: "payments#refund"
    get "/payments", to: "payments#index"
  end
end

class PaymentsController < ActionController::API
  # 70% chance of success
  FAILURE_RATE = 0.3

  def index
    payments = Payment.all.order(created_at: :desc)
    render json: payments
  end

  def create
    order_id = params[:order_id]

    # Simulate random failure
    if rand < FAILURE_RATE
      puts "[PAYMENT] ❌ Payment DECLINED for order #{order_id} (simulated failure)"
      render json: { error: "Payment declined", order_id: order_id }, status: :payment_required
      return
    end

    payment = Payment.create!(order_id: order_id, status: "authorized")
    puts "[PAYMENT] ✅ Payment AUTHORIZED for order #{order_id}"
    render json: payment, status: :created
  end

  def refund
    order_id = params[:order_id]
    payment = Payment.find_by(order_id: order_id)

    if payment
      payment.update!(status: "refunded")
      puts "[PAYMENT] 💰 Payment REFUNDED for order #{order_id}"
      render json: payment
    else
      puts "[PAYMENT] ⚠️ No payment found to refund for order #{order_id}"
      render json: { message: "No payment found", order_id: order_id }
    end
  end
end

PaymentsApp.initialize!

puts "\n" + "=" * 60
puts "💳 PAYMENTS APP starting on port 4001"
puts "=" * 60
puts "Endpoints:"
puts "  POST /payments        - Create payment (#{((1 - PaymentsController::FAILURE_RATE) * 100).to_i}% success rate)"
puts "  POST /payments/refund - Refund payment (compensation)"
puts "  GET  /payments        - List all payments"
puts "=" * 60 + "\n"

Rackup::Server.new(app: PaymentsApp, Port: 4001, Host: "0.0.0.0").start

