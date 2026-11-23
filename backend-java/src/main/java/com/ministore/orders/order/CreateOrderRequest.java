package com.ministore.orders.order;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/** Body de POST /api/orders: { "productId": 1, "quantity": 2, "customerEmail": "user@uce.edu.ec" } */
public record CreateOrderRequest(
        @NotNull Long productId,
        @Min(1) @Max(100) int quantity,
        @NotBlank @Email String customerEmail) {
}
