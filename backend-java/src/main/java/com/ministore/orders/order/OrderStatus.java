package com.ministore.orders.order;

public enum OrderStatus {
    /** El inventario legado confirmo stock suficiente. */
    CONFIRMED,
    /** El inventario legado respondio, pero no hay stock suficiente. */
    OUT_OF_STOCK,
    /** Fallback: el legado fallo o el circuito esta OPEN. La venta no se pierde; se valida despues. */
    PENDING_VALIDATION
}
