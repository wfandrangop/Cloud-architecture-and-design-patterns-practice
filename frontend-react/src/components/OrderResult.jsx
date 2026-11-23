import { StateBadge } from './CircuitPanel.jsx'

const REASON_TEXT = {
  CIRCUIT_OPEN: 'Circuito OPEN: no se contacto al legado',
  TIMEOUT: 'Timeout de 2 s en cada intento',
  LEGACY_ERROR: 'El legado respondio con error',
}

export default function OrderResult({ results }) {
  if (results.length === 0) {
    return (
      <div className="card result empty">
        <p className="muted">El resultado de la orden aparecera aqui: estado, intentos al legado, latencia y tarea Fargate que la atendio.</p>
      </div>
    )
  }
  return (
    <div className="card result">
      <h2>Resultado</h2>
      <ul className="result-list">
        {results.map((o) => (
          <li key={o.id}>
            <div className="result-head">
              <strong>Orden #{o.id}</strong>
              <span className={`status status-${o.status.toLowerCase()}`}>{o.status}</span>
            </div>
            <div className="result-meta">
              <span>Intentos al legado: <b>{o.inventoryAttempts}</b></span>
              <span>Cadena de resiliencia: <b>{o.inventoryLatencyMs} ms</b></span>
              <span>Ida y vuelta: <b>{o.roundTripMs} ms</b></span>
              <span>Tarea: <code>{o.servedBy}</code></span>
              <span>Circuito: <StateBadge state={o.circuitState} /></span>
            </div>
            {o.fallbackReason && <p className="muted small">Fallback: {REASON_TEXT[o.fallbackReason] ?? o.fallbackReason}</p>}
          </li>
        ))}
      </ul>
    </div>
  )
}
