# Distributed Transaction Saga Demo

A minimal demonstration of the **Saga pattern** for distributed transactions using 4 tiny inline Rails apps communicating via HTTP.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                     SAGA ORCHESTRATOR               │
│                      (orders_app)                   │
│                       Port 4000                     │
└──────────────────────────┬──────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│ payments_app  │  │ inventory_app │  │ shipping_app  │
│  Port 4001    │  │  Port 4002    │  │  Port 4003    │
│               │  │               │  │               │
│ POST /payments│  │ POST /reserve │  │ POST /create  │
│ POST /refund  │  │ POST /release │  │               │
└───────────────┘  └───────────────┘  └───────────────┘
```

## The Saga Flow

1. **Order Created** → status: `pending`
2. **Payment** → POST to payments_app → status: `paid`
3. **Inventory** → POST to inventory_app → status: `reserved`
4. **Shipping** → POST to shipping_app → status: `shipped`

### Compensation (on failure)

If any step fails, compensating actions run in reverse order:
- Release inventory reservation
- Refund payment
- Mark order as `failed`

## Quick Start

### 1. Start all services (in separate terminals)

```bash
# Terminal 1 - Payments Service
cd saga_demo/payments_app && ruby app.rb

# Terminal 2 - Inventory Service
cd saga_demo/inventory_app && ruby app.rb

# Terminal 3 - Shipping Service
cd saga_demo/shipping_app && ruby app.rb

# Terminal 4 - Orders Service (Orchestrator)
cd saga_demo/orders_app && ruby app.rb
```

### 2. Create an order

```bash
curl -X POST http://localhost:4000/orders
```

### 3. Watch the saga execute

You'll see logs in each terminal showing the distributed transaction in action!

## API Endpoints

### Orders App (Port 4000)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /orders | Create order and execute saga |
| GET | /orders | List all orders |
| GET | /orders/:id | Get specific order |

### Payments App (Port 4001)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /payments | Create payment (70% success) |
| POST | /payments/refund | Refund payment |
| GET | /payments | List all payments |

### Inventory App (Port 4002)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /inventory/reserve | Reserve inventory (70% success) |
| POST | /inventory/release | Release reservation |
| GET | /inventory | List all reservations |

### Shipping App (Port 4003)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /shipping/create | Create shipment (70% success) |
| GET | /shipping | List all shipments |

## Example Outputs

### Successful Saga
```json
{
  "order": {
    "id": 1,
    "status": "shipped",
    "created_at": "...",
    "updated_at": "..."
  },
  "message": "Order completed successfully"
}
```

### Failed Saga (with compensation)
```json
{
  "order": {
    "id": 2,
    "status": "failed",
    "created_at": "...",
    "updated_at": "..."
  },
  "message": "Order failed",
  "failed_step": "inventory",
  "error": {
    "success": false,
    "data": {"error": "Out of stock", "order_id": 2}
  }
}
```

## Testing Multiple Orders

```bash
# Run 10 orders to see success and failure scenarios
for i in {1..10}; do
  echo "=== Order $i ==="
  curl -s -X POST http://localhost:4000/orders | jq .
  sleep 1
done
```

## Checking State

```bash
# Check all orders
curl http://localhost:4000/orders | jq .

# Check all payments
curl http://localhost:4001/payments | jq .

# Check all inventory reservations
curl http://localhost:4002/inventory | jq .

# Check all shipments
curl http://localhost:4003/shipping | jq .
```

## Key Concepts Demonstrated

1. **Orchestration-based Saga**: The orders_app acts as the central orchestrator
2. **Compensating Transactions**: Each service has a "undo" endpoint for rollback
3. **Synchronous Communication**: Simple HTTP calls, no message queues
4. **Idempotency**: Services handle duplicate requests gracefully
5. **Failure Simulation**: Random failures to demonstrate compensation

## Technology Stack

- Ruby 3.x
- Rails 7.1 (API mode)
- SQLite3 (each service has its own database)
- HTTParty (for HTTP client calls)
- Rack (for serving the apps)
