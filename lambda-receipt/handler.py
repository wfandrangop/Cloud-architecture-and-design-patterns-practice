"""
Lambda "receipt-processor" (Patron 4: Serverless).

La invoca el order-service (Java) de forma asincrona (InvocationType=Event) cada vez que
se registra una orden. Genera el recibo y simula la notificacion al cliente; el resultado
queda en CloudWatch Logs: /aws/lambda/ministore-receipt-processor
"""
import json
import uuid
from datetime import datetime, timezone

MESSAGES = {
    "CONFIRMED": "Tu orden fue confirmada y sera despachada.",
    "OUT_OF_STOCK": "Lo sentimos, no hay stock suficiente para tu orden.",
    "PENDING_VALIDATION": "Recibimos tu orden. Estamos validando el stock y te confirmaremos pronto.",
}


def lambda_handler(event, context):
    status = event.get("status", "UNKNOWN")
    receipt = {
        "receiptId": "RC-" + uuid.uuid4().hex[:10].upper(),
        "orderId": event.get("orderId"),
        "status": status,
        "to": event.get("customerEmail"),
        "subject": "MiniStore Express - Orden #%s" % event.get("orderId"),
        "body": "%s Producto: %s x%s. Total: $%s" % (
            MESSAGES.get(status, "Estado de tu orden: " + status),
            event.get("productName"), event.get("quantity"), event.get("total")),
        "fallbackReason": event.get("fallbackReason"),
        "processedAt": datetime.now(timezone.utc).isoformat(),
        "requestId": getattr(context, "aws_request_id", None),
    }
    # En produccion aqui se llamaria a SES/SNS; en el Learner Lab lo dejamos en CloudWatch.
    print("RECIBO_GENERADO " + json.dumps(receipt, ensure_ascii=False))
    return receipt
