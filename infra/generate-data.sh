#!/bin/bash
# ============================================================
# Data Generator - Simulates real-time e-commerce activity
# Run this AFTER docker-compose is up to generate CDC events
#
# Usage: ./generate-data.sh [num_orders]
# Default: generates 10 orders with related events
# ============================================================

set -e

PGHOST=localhost
PGPORT=5432
PGUSER=cdc_user
PGPASSWORD=cdc_password
PGDATABASE=ecommerce

NUM_ORDERS=${1:-10}
export PGPASSWORD

echo "🚀 Generating $NUM_ORDERS orders with related events..."
echo "   Watch the Flink UI at http://localhost:8081 to see data flowing"
echo ""

for i in $(seq 1 $NUM_ORDERS); do
    # Random customer (1-5) and product (1-8)
    CUSTOMER_ID=$((RANDOM % 5 + 1))
    PRODUCT_ID=$((RANDOM % 8 + 1))
    QUANTITY=$((RANDOM % 5 + 1))
    
    echo "--- Order $i ---"
    
    # 1. Create order
    ORDER_ID=$(psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -A -c "
        INSERT INTO ecommerce.orders (customer_id, order_status, total_amount)
        VALUES ($CUSTOMER_ID, 'PENDING', 0)
        RETURNING order_id;
    ")
    echo "  Created order: $ORDER_ID for customer: $CUSTOMER_ID"
    
    # 2. Add order items
    psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -c "
        INSERT INTO ecommerce.order_items (order_id, product_id, quantity, unit_price)
        SELECT $ORDER_ID, product_id, $QUANTITY, price
        FROM ecommerce.products WHERE product_id = $PRODUCT_ID;
    " > /dev/null
    echo "  Added item: product $PRODUCT_ID x $QUANTITY"
    
    # 3. Update order total
    psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -c "
        UPDATE ecommerce.orders SET 
            total_amount = (SELECT SUM(quantity * unit_price) FROM ecommerce.order_items WHERE order_id = $ORDER_ID),
            order_status = 'CONFIRMED',
            updated_at = NOW()
        WHERE order_id = $ORDER_ID;
    " > /dev/null
    echo "  Order confirmed"
    
    # 4. Process payment
    PAYMENT_METHODS=("CREDIT_CARD" "DEBIT_CARD" "PAYPAL" "BANK_TRANSFER")
    METHOD=${PAYMENT_METHODS[$((RANDOM % 4))]}
    psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -c "
        INSERT INTO ecommerce.payments (order_id, payment_method, payment_status, amount)
        SELECT $ORDER_ID, '$METHOD', 'COMPLETED', total_amount
        FROM ecommerce.orders WHERE order_id = $ORDER_ID;
    " > /dev/null
    echo "  Payment: $METHOD"
    
    # 5. Create inventory event
    WAREHOUSE_ID=$((RANDOM % 3 + 1))
    psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -c "
        INSERT INTO ecommerce.inventory_events (product_id, warehouse_id, event_type, quantity_change)
        VALUES ($PRODUCT_ID, $WAREHOUSE_ID, 'SALE', -$QUANTITY);
    " > /dev/null
    echo "  Inventory updated: warehouse $WAREHOUSE_ID"
    
    # 6. Create shipment (50% chance of immediate shipment)
    if [ $((RANDOM % 2)) -eq 0 ]; then
        psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -c "
            INSERT INTO ecommerce.shipments (order_id, warehouse_id, carrier, tracking_number, shipment_status, shipped_at)
            VALUES ($ORDER_ID, $WAREHOUSE_ID, 'UPS', 'TRK${ORDER_ID}$(date +%s)', 'SHIPPED', NOW());
        " > /dev/null
        
        psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -c "
            UPDATE ecommerce.orders SET order_status = 'SHIPPED', updated_at = NOW()
            WHERE order_id = $ORDER_ID;
        " > /dev/null
        echo "  Shipped via UPS"
    fi
    
    echo ""
    
    # Small delay to simulate real-time activity
    sleep 1
done

echo "✅ Done! Generated $NUM_ORDERS orders"
echo ""
echo "📊 Summary:"
psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -c "
    SELECT 
        (SELECT COUNT(*) FROM ecommerce.orders) as total_orders,
        (SELECT COUNT(*) FROM ecommerce.order_items) as total_items,
        (SELECT COUNT(*) FROM ecommerce.payments) as total_payments,
        (SELECT COUNT(*) FROM ecommerce.shipments) as total_shipments,
        (SELECT COUNT(*) FROM ecommerce.inventory_events) as total_inventory_events;
"
