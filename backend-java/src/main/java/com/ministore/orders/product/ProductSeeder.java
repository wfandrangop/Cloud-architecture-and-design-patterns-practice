package com.ministore.orders.product;

import java.math.BigDecimal;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/** Carga los 4 productos de prueba si la tabla esta vacia (RDS recien creado). */
@Component
public class ProductSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(ProductSeeder.class);
    private final ProductRepository repository;

    public ProductSeeder(ProductRepository repository) {
        this.repository = repository;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (repository.count() > 0) {
            return;
        }
        repository.saveAll(List.of(
                new Product(1L, "Laptop UltraBook 14\"", "Intel Core i7, 16 GB RAM, SSD 512 GB", new BigDecimal("899.99")),
                new Product(2L, "Monitor 27\" 4K", "Panel IPS, USB-C 65 W", new BigDecimal("329.50")),
                new Product(3L, "Teclado mecanico", "Switches red, layout ES", new BigDecimal("79.90")),
                new Product(4L, "Mouse inalambrico", "Bluetooth + 2.4 GHz, 4000 DPI", new BigDecimal("29.99"))));
        log.info("Catalogo inicial cargado (4 productos)");
    }
}
