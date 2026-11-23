package com.ministore.orders.support;

import java.net.InetAddress;
import java.net.UnknownHostException;

import org.springframework.stereotype.Component;

/** Identifica la tarea Fargate (hostname = ip-10-1-x-x) para evidenciar el balanceo del ALB. */
@Component
public class InstanceInfo {

    private final String hostname;

    public InstanceInfo() {
        String name;
        try {
            name = InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            name = "unknown";
        }
        this.hostname = name;
    }

    public String hostname() {
        return hostname;
    }
}
