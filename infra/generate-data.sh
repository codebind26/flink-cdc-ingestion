#!/bin/bash
# ============================================================
# Data Generator - Simulates real-time e-commerce activity
# Runs psql inside the postgres-source Docker container
#
# Usage: ./generate-data.sh [num_orders]
# ============================================================

set -e

CONTAINER=postgres-source
PGUSER=cdc_user
PGDATABASE=ecommerce
NUM_ORDERS=${1:-10}

run_sql() {
    docker exec -e PGPASSWORD=cdc_password "$CONTAINER" \
        psql -h localhost -U "$PGUSER" -d "$PGDATABASE" -t -A -c "$1"
}

echo "🚀 Generating $NUM_ORDERS orders with related events..."
echo ""

for i in $(seq 1 $NUM_ORDERS); do
    CUSTOMER_ID=$((RANDOM % 5 + 1))
    PRODUCT_ID=$((RANDOM % 8 + 1))
    QUANTITY=$((RANDOM % 5 + 1))
    WAREHOUSE_ID=$((RANDOM % 3 + 1))
    METHODS=("CREDIT_CARD" "DEBIT_CARD" "PAYPAL" "BANK_TRANSFER")
    METHOD=${METHODS[$((RANDOM % 4))]}

    echo "--- Order $i ---"

    ORDER_ID=$(run_sql "
        INSERT INTO ecommerce.orders (customer_id, order_status, total_amount)
        VALUES ($CUSTOMER_ID, 'PENDING', 0)
        RETURNING order_id;
    " | grep -E '^[0-9]+$' | tr -d '[:space:]')
    echo "  Created order: $ORDER_ID for customer: $CUSTOMER_ID"

    run_sql "
        INSERT INTO ecommerce.order_items (order_id, product_id, quantity, unit_price)
        SELECT $ORDER_ID, product_id, $QUANTITY, price
        FROM ecommerce.products WHERE product_id = $PRODUCT_ID;
    " > /dev/null

    run_sql "
        UPDATE ecommerce.orders SET
            total_amount = (SELECT SUM(quantity * unit_price) FROM ecommerce.order_items WHERE order_id = $ORDER_ID),
            order_status = 'CONFIRMED',
            updated_at = NOW()
        WHERE order_id = $ORDER_ID;
    " > /dev/null
    echo "  Confirmed, payment: $METHOD"

    run_sql "
        INSERT INTO ecommerce.payments (order_id, payment_method, payment_status, amount)
        SELECT $ORDER_ID, '$METHOD', 'COMPLETED', total_amount
        FROM ecommerce.orders WHERE order_id = $ORDER_ID;
    " > /dev/null

    run_sql "
        INSERT INTO ecommerce.inventory_events (product_id, warehouse_id, event_type, quantity_change)
        VALUES ($PRODUCT_ID, $WAREHOUSE_ID, 'SALE', -$QUANTITY);
    " > /dev/null

    if [ $((RANDOM % 2)) -eq 0 ]; then
        run_sql "
            INSERT INTO ecommerce.shipments (order_id, warehouse_id, carrier, tracking_number, shipment_status, shipped_at)
            VALUES ($ORDER_ID, $WAREHOUSE_ID, 'UPS', 'TRK${ORDER_ID}${RANDOM}', 'SHIPPED', NOW());
            UPDATE ecommerce.orders SET order_status = 'SHIPPED', updated_at = NOW()
            WHERE order_id = $ORDER_ID;
        " > /dev/null
        echo "  Shipped via UPS"
    fi

    echo ""
    sleep 1
done

echo "✅ Done! Generated $NUM_ORDERS orders"
echo ""
echo "📊 Summary:"
run_sql "
    SELECT 'orders: ' || COUNT(*) FROM ecommerce.orders
    UNION ALL
    SELECT 'items: ' || COUNT(*) FROM ecommerce.order_items
    UNION ALL
    SELECT 'payments: ' || COUNT(*) FROM ecommerce.payments
    UNION ALL
    SELECT 'shipments: ' || COUNT(*) FROM ecommerce.shipments
    UNION ALL
    SELECT 'inventory: ' || COUNT(*) FROM ecommerce.inventory_events;
"
