package com.ministore.orders.inventory;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/** Respuesta del sistema heredado: GET /inventory/{id}. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record InventoryResponse(long productId, int stock, String warehouse) {
}
