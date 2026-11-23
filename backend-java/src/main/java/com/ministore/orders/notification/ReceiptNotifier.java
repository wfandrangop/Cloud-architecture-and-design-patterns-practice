package com.ministore.orders.notification;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.ministore.orders.order.PurchaseOrder;

import jakarta.annotation.PreDestroy;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.lambda.LambdaClient;
import software.amazon.awssdk.services.lambda.model.InvocationType;
import software.amazon.awssdk.services.lambda.model.InvokeRequest;
import software.amazon.awssdk.services.lambda.model.InvokeResponse;
import tools.jackson.databind.json.JsonMapper;

/**
 * Patron 4 (Serverless): invoca la Lambda "receipt-processor" con InvocationType.EVENT
 * (asincrona, "fire and forget"). Se ejecuta en un hilo aparte para no sumar latencia
 * a la respuesta HTTP: la orden ya esta guardada en RDS cuando se notifica.
 *
 * Credenciales: cadena por defecto del SDK -> en ECS Fargate usa el task role (LabRole).
 * Si ministore.lambda.function-name esta vacio (perfil local) solo se registra en el log.
 */
@Component
public class ReceiptNotifier {

    private static final Logger log = LoggerFactory.getLogger(ReceiptNotifier.class);

    private final String functionName;
    private final LambdaClient lambda;
    private final JsonMapper jsonMapper;
    private final ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();

    public ReceiptNotifier(@Value("${ministore.lambda.function-name:}") String functionName,
                           @Value("${ministore.lambda.region:us-east-1}") String region,
                           JsonMapper jsonMapper) {
        this.functionName = functionName;
        this.jsonMapper = jsonMapper;
        this.lambda = functionName.isBlank() ? null
                : LambdaClient.builder().region(Region.of(region)).build();
    }

    public void notifyAsync(PurchaseOrder order) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("orderId", order.getId());
        payload.put("status", order.getStatus().name());
        payload.put("customerEmail", order.getCustomerEmail());
        payload.put("productName", order.getProductName());
        payload.put("quantity", order.getQuantity());
        payload.put("total", order.getTotal());
        payload.put("fallbackReason", order.getFallbackReason());
        payload.put("createdAt", order.getCreatedAt().toString());

        executor.submit(() -> invoke(order.getId(), payload));
    }

    private void invoke(Long orderId, Map<String, Object> payload) {
        String json = jsonMapper.writeValueAsString(payload);
        if (lambda == null) {
            log.info("[LAMBDA] deshabilitada (sin function-name). Payload orden {}: {}", orderId, json);
            return;
        }
        try {
            InvokeResponse response = lambda.invoke(InvokeRequest.builder()
                    .functionName(functionName)
                    .invocationType(InvocationType.EVENT)
                    .payload(SdkBytes.fromUtf8String(json))
                    .build());
            log.info("[LAMBDA] {} invocada para orden {} (HTTP {})", functionName, orderId, response.statusCode());
        } catch (Exception e) {
            // La notificacion es "best effort": un fallo aqui no revierte la orden.
            log.error("[LAMBDA] error invocando {} para orden {}: {}", functionName, orderId, e.toString());
        }
    }

    @PreDestroy
    void shutdown() {
        executor.shutdown();
        if (lambda != null) {
            lambda.close();
        }
    }
}
