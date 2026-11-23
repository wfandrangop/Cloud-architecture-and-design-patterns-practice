package com.ministore.orders.inventory;

import java.net.http.HttpClient;
import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/**
 * Cliente HTTP "crudo" hacia el inventario heredado (EC2 Lift-and-Shift).
 * No tiene logica de resiliencia: eso lo agrega {@link ResilientInventoryService}.
 *
 * El read-timeout del socket (3s) es solo una red de seguridad para liberar el hilo;
 * el Timeout del patron (2s) lo impone el TimeLimiter de Resilience4j.
 */
@Component
public class LegacyInventoryClient {

    private final RestClient restClient;

    public LegacyInventoryClient(
            @Value("${ministore.legacy.base-url}") String baseUrl,
            @Value("${ministore.legacy.connect-timeout:1s}") Duration connectTimeout,
            @Value("${ministore.legacy.read-timeout:3s}") Duration readTimeout) {

        HttpClient httpClient = HttpClient.newBuilder()
                .connectTimeout(connectTimeout)
                .version(HttpClient.Version.HTTP_1_1)
                .build();
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(httpClient);
        factory.setReadTimeout(readTimeout);

        this.restClient = RestClient.builder()
                .baseUrl(baseUrl)
                .requestFactory(factory)
                .build();
    }

    public InventoryResponse getInventory(long productId) {
        return restClient.get()
                .uri("/inventory/{id}", productId)
                .retrieve()
                .body(InventoryResponse.class);
    }
}
