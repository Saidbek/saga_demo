#!/bin/bash

# Start all Saga services
# Run this script, then each service will start in its own process

echo "Starting Saga Demo Services..."
echo "=============================="
echo ""
echo "Starting services in background..."
echo "Press Ctrl+C to stop all services"
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Stopping all services..."
    pkill -f "saga_demo.*app.rb"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start services
cd "$(dirname "$0")"

echo "Starting Payments App on port 4001..."
(cd payments_app && ruby app.rb 2>&1 | sed 's/^/[payments] /') &

echo "Starting Inventory App on port 4002..."
(cd inventory_app && ruby app.rb 2>&1 | sed 's/^/[inventory] /') &

echo "Starting Shipping App on port 4003..."
(cd shipping_app && ruby app.rb 2>&1 | sed 's/^/[shipping] /') &

# Wait for services to initialize
sleep 10

echo "Starting Orders App on port 4000..."
(cd orders_app && ruby app.rb 2>&1 | sed 's/^/[orders] /') &

# Wait for all background processes
wait

