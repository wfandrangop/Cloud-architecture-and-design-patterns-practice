export default function OrdersTable({ orders }) {
  if (orders.length === 0) return <p className="muted">Aun no hay ordenes.</p>
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>#</th><th>Producto</th><th>Cant.</th><th>Total</th><th>Estado</th>
            <th>Fallback</th><th>Intentos</th><th>ms</th><th>Tarea</th><th>Fecha</th>
          </tr>
        </thead>
        <tbody>
          {orders.map((o) => (
            <tr key={o.id}>
              <td>{o.id}</td>
              <td>{o.productName}</td>
              <td>{o.quantity}</td>
              <td>${Number(o.total).toFixed(2)}</td>
              <td><span className={`status status-${o.status.toLowerCase()}`}>{o.status}</span></td>
              <td>{o.fallbackReason ?? '—'}</td>
              <td>{o.inventoryAttempts}</td>
              <td>{o.inventoryLatencyMs}</td>
              <td><code>{o.servedBy}</code></td>
              <td>{new Date(o.createdAt).toLocaleTimeString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
