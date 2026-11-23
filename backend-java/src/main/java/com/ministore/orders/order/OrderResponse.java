package com.ministore.orders.order;

import java.math.BigDecimal;
import java.time.Instant;

public record OrderResponse(
        Long id,
        Long productId,
        String productName,
        int quantity,
        BigDecimal total,
        String customerEmail,
        OrderStatus status,
        String fallbackReason,
        int inventoryAttempts,
        long inventoryLatencyMs,
        String servedBy,
        Instant createdAt,
        String circuitState) {

    public static OrderResponse from(PurchaseOrder o, String circuitState) {
        return new OrderResponse(o.getId(), o.getProductId(), o.getProductName(), o.getQuantity(),
                o.getTotal(), o.getCustomerEmail(), o.getStatus(), o.getFallbackReason(),
                o.getInventoryAttempts(), o.getInventoryLatencyMs(), o.getServedBy(),
                o.getCreatedAt(), circuitState);
    }
}
