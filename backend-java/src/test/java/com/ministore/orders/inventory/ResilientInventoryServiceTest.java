package com.ministore.orders.inventory;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.HttpServerErrorException;

import com.ministore.orders.inventory.InventoryCheck.FallbackReason;
import com.sun.net.httpserver.HttpServer;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.retry.RetryConfig;
import io.github.resilience4j.retry.RetryRegistry;
import io.github.resilience4j.timelimiter.TimeLimiterConfig;
import io.github.resilience4j.timelimiter.TimeLimiterRegistry;

/**
 * Prueba la cadena CircuitBreaker -> Retry -> TimeLimiter contra un "legado" HTTP falso.
 * Usa los mismos valores que application.yml, salvo el timeout (300 ms en vez de 2 s)
 * para que el test sea rapido.
 */
class ResilientInventoryServiceTest {

    private HttpServer legacy;
    private final AtomicReference<String> mode = new AtomicReference<>("normal");
    private final AtomicInteger hits = new AtomicInteger();
    private ResilientInventoryService service;

    @BeforeEach
    void setUp() throws IOException {
        legacy = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        legacy.setExecutor(java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor());
        legacy.createContext("/inventory/", exchange -> {
            hits.incrementAndGet();
            try {
                switch (mode.get()) {
                    case "slow" -> Thread.sleep(1_000);
                    case "down" -> {
                        exchange.sendResponseHeaders(500, -1);
                        exchange.close();
                        return;
                    }
                    default -> { }
                }
                byte[] body = "{\"productId\":1,\"stock\":10,\"warehouse\":\"QUITO\"}".getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().add("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, body.length);
                exchange.getResponseBody().write(body);
            } catch (Exception ignored) {
                // el cliente corto la conexion por timeout
            } finally {
                exchange.close();
            }
        });
        legacy.start();

        String baseUrl = "http://127.0.0.1:" + legacy.getAddress().getPort();
        LegacyInventoryClient client = new LegacyInventoryClient(baseUrl, Duration.ofSeconds(1), Duration.ofSeconds(3));

        CircuitBreakerConfig cbConfig = CircuitBreakerConfig.custom()
                .slidingWindowType(CircuitBreakerConfig.SlidingWindowType.COUNT_BASED)
                .slidingWindowSize(4)
                .minimumNumberOfCalls(3)
                .failureRateThreshold(50)
                .waitDurationInOpenState(Duration.ofSeconds(15))
                .build();
        RetryConfig retryConfig = RetryConfig.custom()
                .maxAttempts(3)
                .waitDuration(Duration.ofMillis(500))
                .retryExceptions(java.util.concurrent.TimeoutException.class, HttpServerErrorException.class,
                        IOException.class, org.springframework.web.client.ResourceAccessException.class)
                .build();
        TimeLimiterConfig tlConfig = TimeLimiterConfig.custom()
                .timeoutDuration(Duration.ofMillis(300))
                .cancelRunningFuture(true)
                .build();

        service = new ResilientInventoryService(client,
                CircuitBreakerRegistry.of(cbConfig), RetryRegistry.of(retryConfig), TimeLimiterRegistry.of(tlConfig));
    }

    @AfterEach
    void tearDown() {
        legacy.stop(0);
        service.shutdown();
    }

    @Test
    void normalModeConfirmsStockInOneAttempt() {
        InventoryCheck check = service.checkStock(1, 2);

        assertThat(check.verified()).isTrue();
        assertThat(check.available()).isTrue();
        assertThat(check.stock()).isEqualTo(10);
        assertThat(check.attempts()).isEqualTo(1);
    }

    @Test
    void slowModeTimesOutEachAttemptAndRetriesThreeTimes() {
        mode.set("slow");

        InventoryCheck check = service.checkStock(1, 1);

        assertThat(check.verified()).isFalse();
        assertThat(check.fallbackReason()).isEqualTo(FallbackReason.TIMEOUT);
        assertThat(check.attempts()).isEqualTo(3);
        // 3 x 300 ms (timeout) + 2 x 500 ms (espera) ~= 1.9 s, y nunca el 1 s completo del legado por intento
        assertThat(check.latencyMs()).isBetween(1_800L, 2_800L);
    }

    @Test
    void downModeOpensCircuitAndFourthOrderSkipsLegacy() {
        mode.set("down");

        for (int i = 0; i < 3; i++) {
            InventoryCheck check = service.checkStock(1, 1);
            assertThat(check.fallbackReason()).isEqualTo(FallbackReason.LEGACY_ERROR);
            assertThat(check.attempts()).isEqualTo(3);
        }
        assertThat(service.circuitBreaker().getState()).isEqualTo(CircuitBreaker.State.OPEN);
        int hitsBefore = hits.get();

        InventoryCheck fourth = service.checkStock(1, 1);

        assertThat(fourth.fallbackReason()).isEqualTo(FallbackReason.CIRCUIT_OPEN);
        assertThat(fourth.attempts()).isZero();
        assertThat(fourth.latencyMs()).isLessThan(20);
        assertThat(hits.get()).isEqualTo(hitsBefore);   // no se toco el legado caido
    }
}
