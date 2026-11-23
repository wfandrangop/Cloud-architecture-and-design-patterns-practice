package com.ministore.orders.order;

import java.math.BigDecimal;
import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "purchase_orders")
public class PurchaseOrder {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long productId;

    @Column(nullable = false, length = 120)
    private String productName;

    @Column(nullable = false)
    private int quantity;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal total;

    @Column(nullable = false, length = 160)
    private String customerEmail;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private OrderStatus status;

    /** CIRCUIT_OPEN | TIMEOUT | LEGACY_ERROR cuando se ejecuto el fallback. */
    @Column(length = 30)
    private String fallbackReason;

    private int inventoryAttempts;

    private long inventoryLatencyMs;

    /** Hostname de la tarea Fargate que atendio la orden (evidencia del balanceo del ALB). */
    @Column(length = 120)
    private String servedBy;

    @Column(nullable = false)
    private Instant createdAt;

    protected PurchaseOrder() {
    }

    public PurchaseOrder(Long productId, String productName, int quantity, BigDecimal total,
                         String customerEmail, OrderStatus status, String fallbackReason,
                         int inventoryAttempts, long inventoryLatencyMs, String servedBy) {
        this.productId = productId;
        this.productName = productName;
        this.quantity = quantity;
        this.total = total;
        this.customerEmail = customerEmail;
        this.status = status;
        this.fallbackReason = fallbackReason;
        this.inventoryAttempts = inventoryAttempts;
        this.inventoryLatencyMs = inventoryLatencyMs;
        this.servedBy = servedBy;
        this.createdAt = Instant.now();
    }

    public Long getId() { return id; }
    public Long getProductId() { return productId; }
    public String getProductName() { return productName; }
    public int getQuantity() { return quantity; }
    public BigDecimal getTotal() { return total; }
    public String getCustomerEmail() { return customerEmail; }
    public OrderStatus getStatus() { return status; }
    public String getFallbackReason() { return fallbackReason; }
    public int getInventoryAttempts() { return inventoryAttempts; }
    public long getInventoryLatencyMs() { return inventoryLatencyMs; }
    public String getServedBy() { return servedBy; }
    public Instant getCreatedAt() { return createdAt; }
}
