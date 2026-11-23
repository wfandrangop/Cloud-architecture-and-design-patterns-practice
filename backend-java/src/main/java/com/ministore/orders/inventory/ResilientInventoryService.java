package com.ministore.orders.inventory;

import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.ministore.orders.inventory.InventoryCheck.FallbackReason;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.retry.Retry;
import io.github.resilience4j.retry.RetryRegistry;
import io.github.resilience4j.timelimiter.TimeLimiter;
import io.github.resilience4j.timelimiter.TimeLimiterRegistry;
import jakarta.annotation.PreDestroy;

/**
 * Patrones 1, 2 y 3: Circuit Breaker -> Retry -> Timeout.
 *
 * <pre>
 *   CircuitBreaker            (externo)  si esta OPEN corta en ~0 ms sin tocar la red
 *     └─ Retry                           hasta 3 intentos, 500 ms entre intentos
 *          └─ TimeLimiter     (interno)  cada intento se corta a los 2 s
 *               └─ HTTP GET /inventory/{id}  -> EC2 legacy (via NLB de transito del Hub)
 * </pre>
 *
 * Se usa el estilo funcional de Resilience4j (en vez de anotaciones) para garantizar
 * este orden exacto: con anotaciones, el orden por defecto es Retry(CircuitBreaker(...)).
 * La configuracion (umbrales, tiempos) vive en application.yml y la carga el starter
 * resilience4j-spring-boot4 en los registries que se inyectan aqui.
 *
 * Como el Circuit Breaker es el decorador externo, una orden con 3 reintentos fallidos
 * cuenta como UNA llamada fallida en la ventana deslizante del circuito.
 */
@Service
public class ResilientInventoryService {

    public static final String INSTANCE = "legacyInventory";
    private static final Logger log = LoggerFactory.getLogger(ResilientInventoryService.class);

    private final LegacyInventoryClient client;
    private final CircuitBreaker circuitBreaker;
    private final Retry retry;
    private final TimeLimiter timeLimiter;
    /** Hilos virtuales: el TimeLimiter cancela (interrumpe) el intento que excede los 2 s. */
    private final ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();

    public ResilientInventoryService(LegacyInventoryClient client,
                                     CircuitBreakerRegistry circuitBreakerRegistry,
                                     RetryRegistry retryRegistry,
                                     TimeLimiterRegistry timeLimiterRegistry) {
        this.client = client;
        this.circuitBreaker = circuitBreakerRegistry.circuitBreaker(INSTANCE);
        this.retry = retryRegistry.retry(INSTANCE);
        this.timeLimiter = timeLimiterRegistry.timeLimiter(INSTANCE);
        registerEventLogging();
    }

    public InventoryCheck checkStock(long productId, int quantity) {
        long start = System.nanoTime();
        AtomicInteger attempts = new AtomicInteger();

        // 3) Timeout: cada intento corre en un hilo virtual y se cancela a los 2 s
        Callable<InventoryResponse> withTimeout = TimeLimiter.decorateFutureSupplier(timeLimiter,
                () -> executor.submit(() -> {
                    int attempt = attempts.incrementAndGet();
                    log.info("[LEGACY] intento {} -> GET /inventory/{}", attempt, productId);
                    return client.getInventory(productId);
                }));

        // 2) Retry alrededor del intento con timeout
        Callable<InventoryResponse> withRetry = Retry.decorateCallable(retry, withTimeout);

        // 1) Circuit Breaker como capa externa
        Callable<InventoryResponse> guarded = CircuitBreaker.decorateCallable(circuitBreaker, withRetry);

        try {
            InventoryResponse response = guarded.call();
            InventoryCheck check = InventoryCheck.verified(response.stock(), quantity, attempts.get(), elapsedMs(start));
            log.info("[LEGACY] stock producto {} = {} (intentos={}, {} ms)",
                    productId, response.stock(), check.attempts(), check.latencyMs());
            return check;
        } catch (Exception ex) {
            return fallback(productId, ex, attempts.get(), elapsedMs(start));
        }
    }

    /** Plan de respaldo: la orden NO se pierde, queda PENDING_VALIDATION. */
    private InventoryCheck fallback(long productId, Exception ex, int attempts, long latencyMs) {
        FallbackReason reason;
        if (ex instanceof CallNotPermittedException) {
            reason = FallbackReason.CIRCUIT_OPEN;
        } else if (ex instanceof TimeoutException) {
            reason = FallbackReason.TIMEOUT;
        } else {
            reason = FallbackReason.LEGACY_ERROR;
        }
        log.warn("[FALLBACK] producto {} -> {} tras {} intento(s) en {} ms (causa: {})",
                productId, reason, attempts, latencyMs, ex.toString());
        return InventoryCheck.fallback(reason, attempts, latencyMs);
    }

    public CircuitBreaker circuitBreaker() {
        return circuitBreaker;
    }

    private void registerEventLogging() {
        timeLimiter.getEventPublisher().onTimeout(e ->
                log.warn("[TIMEOUT] el legado no respondio en {} ms; intento cancelado",
                        timeLimiter.getTimeLimiterConfig().getTimeoutDuration().toMillis()));

        retry.getEventPublisher().onRetry(e ->
                log.warn("[RETRY] intento {} fallo ({}); reintentando en {} ms",
                        e.getNumberOfRetryAttempts(), simpleName(e.getLastThrowable()),
                        e.getWaitInterval().toMillis()));
        retry.getEventPublisher().onError(e ->
                log.error("[RETRY] agotados {} intentos; ultimo error: {}",
                        e.getNumberOfRetryAttempts(), simpleName(e.getLastThrowable())));

        circuitBreaker.getEventPublisher().onStateTransition(e ->
                log.warn("[CIRCUIT BREAKER] {} -> {}",
                        e.getStateTransition().getFromState(), e.getStateTransition().getToState()));
        circuitBreaker.getEventPublisher().onCallNotPermitted(e ->
                log.warn("[CIRCUIT BREAKER] OPEN: llamada rechazada sin contactar al legado"));
    }

    private static String simpleName(Throwable t) {
        return t == null ? "desconocido" : t.getClass().getSimpleName() + ": " + t.getMessage();
    }

    private static long elapsedMs(long startNanos) {
        return (System.nanoTime() - startNanos) / 1_000_000;
    }

    @PreDestroy
    void shutdown() {
        executor.shutdownNow();
    }
}
