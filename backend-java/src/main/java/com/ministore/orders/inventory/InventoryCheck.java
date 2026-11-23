package com.ministore.orders.inventory;

/**
 * Resultado de consultar el inventario heredado a traves de la cadena de resiliencia.
 *
 * @param verified   true si el inventario respondio; false si se ejecuto el fallback
 * @param available  hay stock suficiente (solo tiene sentido si verified = true)
 * @param stock      stock reportado por el legado (-1 si no respondio)
 * @param fallbackReason motivo del fallback (null si verified = true)
 * @param attempts   intentos HTTP reales hacia el legado (0 si el circuito estaba OPEN)
 * @param latencyMs  tiempo total de la cadena CircuitBreaker -> Retry -> TimeLimiter
 */
public record InventoryCheck(
        boolean verified,
        boolean available,
        int stock,
        FallbackReason fallbackReason,
        int attempts,
        long latencyMs) {

    public enum FallbackReason {
        /** El Circuit Breaker estaba OPEN: ni siquiera se intento llamar al legado. */
        CIRCUIT_OPEN,
        /** Todos los intentos superaron el TimeLimiter (2s). */
        TIMEOUT,
        /** El legado respondio con error (5xx) o hubo un error de red tras los reintentos. */
        LEGACY_ERROR
    }

    public static InventoryCheck verified(int stock, int quantity, int attempts, long latencyMs) {
        return new InventoryCheck(true, stock >= quantity, stock, null, attempts, latencyMs);
    }

    public static InventoryCheck fallback(FallbackReason reason, int attempts, long latencyMs) {
        return new InventoryCheck(false, false, -1, reason, attempts, latencyMs);
    }
}
