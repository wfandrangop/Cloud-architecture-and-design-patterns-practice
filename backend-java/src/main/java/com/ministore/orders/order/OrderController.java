package com.ministore.orders.order;

import java.util.List;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.ministore.orders.inventory.ResilientInventoryService;
import com.ministore.orders.support.InstanceInfo;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private final OrderService orderService;
    private final ResilientInventoryService inventory;
    private final InstanceInfo instance;

    public OrderController(OrderService orderService, ResilientInventoryService inventory, InstanceInfo instance) {
        this.orderService = orderService;
        this.inventory = inventory;
        this.instance = instance;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public OrderResponse create(@Valid @RequestBody CreateOrderRequest request) {
        return orderService.create(request);
    }

    @GetMapping
    public List<OrderResponse> recent() {
        return orderService.recent();
    }

    /**
     * Estado del Circuit Breaker de ESTA tarea Fargate (cada tarea tiene su propio circuito).
     * React lo consulta cada 2 s para pintar el badge CLOSED / OPEN / HALF_OPEN.
     */
    @GetMapping("/health-circuit")
    public Map<String, Object> circuit() {
        CircuitBreaker cb = inventory.circuitBreaker();
        CircuitBreaker.Metrics m = cb.getMetrics();
        return Map.of(
                "state", cb.getState().name(),
                "failureRate", m.getFailureRate(),
                "bufferedCalls", m.getNumberOfBufferedCalls(),
                "failedCalls", m.getNumberOfFailedCalls(),
                "notPermittedCalls", m.getNumberOfNotPermittedCalls(),
                "slidingWindowSize", cb.getCircuitBreakerConfig().getSlidingWindowSize(),
                "servedBy", instance.hostname());
    }
}
