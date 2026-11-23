package com.ministore.orders;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import com.ministore.orders.inventory.ResilientInventoryService;

import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.retry.RetryRegistry;
import io.github.resilience4j.timelimiter.TimeLimiterRegistry;

/** Verifica que el contexto arranca (perfil local/H2) y que application.yml configura los patrones. */
@SpringBootTest
@ActiveProfiles("local")
class OrderServiceApplicationTest {

    @Autowired CircuitBreakerRegistry circuitBreakers;
    @Autowired RetryRegistry retries;
    @Autowired TimeLimiterRegistry timeLimiters;

    @Test
    void resiliencePatternsAreConfiguredFromYaml() {
        var cb = circuitBreakers.circuitBreaker(ResilientInventoryService.INSTANCE).getCircuitBreakerConfig();
        assertThat(cb.getSlidingWindowSize()).isEqualTo(4);
        assertThat(cb.getFailureRateThreshold()).isEqualTo(50f);
        assertThat(cb.getMinimumNumberOfCalls()).isEqualTo(3);

        assertThat(retries.retry(ResilientInventoryService.INSTANCE).getRetryConfig().getMaxAttempts()).isEqualTo(3);

        assertThat(timeLimiters.timeLimiter(ResilientInventoryService.INSTANCE).getTimeLimiterConfig().getTimeoutDuration())
                .isEqualTo(Duration.ofSeconds(2));
    }
}
