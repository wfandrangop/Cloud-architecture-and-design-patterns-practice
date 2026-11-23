package com.ministore.orders.order;

import java.math.BigDecimal;
import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import com.ministore.orders.inventory.InventoryCheck;
import com.ministore.orders.inventory.ResilientInventoryService;
import com.ministore.orders.notification.ReceiptNotifier;
import com.ministore.orders.product.Product;
import com.ministore.orders.product.ProductRepository;
import com.ministore.orders.support.InstanceInfo;

@Service
public class OrderService {

    private final ProductRepository products;
    private final OrderRepository orders;
    private final ResilientInventoryService inventory;
    private final ReceiptNotifier receiptNotifier;
    private final InstanceInfo instance;

    public OrderService(ProductRepository products, OrderRepository orders,
                        ResilientInventoryService inventory, ReceiptNotifier receiptNotifier,
                        InstanceInfo instance) {
        this.products = products;
        this.orders = orders;
        this.inventory = inventory;
        this.receiptNotifier = receiptNotifier;
        this.instance = instance;
    }

    public OrderResponse create(CreateOrderRequest request) {
        Product product = products.findById(request.productId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Producto " + request.productId() + " no existe"));

        // Consulta al inventario heredado protegida por CircuitBreaker -> Retry -> Timeout
        InventoryCheck check = inventory.checkStock(product.getId(), request.quantity());

        OrderStatus status;
        if (!check.verified()) {
            status = OrderStatus.PENDING_VALIDATION;   // fallback: aceptamos la venta
        } else if (check.available()) {
            status = OrderStatus.CONFIRMED;
        } else {
            status = OrderStatus.OUT_OF_STOCK;
        }

        BigDecimal total = product.getPrice().multiply(BigDecimal.valueOf(request.quantity()));
        PurchaseOrder saved = orders.save(new PurchaseOrder(
                product.getId(), product.getName(), request.quantity(), total,
                request.customerEmail(), status,
                check.fallbackReason() == null ? null : check.fallbackReason().name(),
                check.attempts(), check.latencyMs(), instance.hostname()));

        // Serverless: la Lambda genera el recibo / notificacion de forma asincrona
        receiptNotifier.notifyAsync(saved);

        return OrderResponse.from(saved, inventory.circuitBreaker().getState().name());
    }

    public List<OrderResponse> recent() {
        String state = inventory.circuitBreaker().getState().name();
        return orders.findTop20ByOrderByIdDesc().stream()
                .map(o -> OrderResponse.from(o, state))
                .toList();
    }
}
