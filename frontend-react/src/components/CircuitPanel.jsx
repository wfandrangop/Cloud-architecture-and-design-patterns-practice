const STALE_MS = 60_000

export function StateBadge({ state }) {
  return <span className={`badge badge-${(state ?? 'unknown').toLowerCase()}`}>{state ?? '—'}</span>
}

/** Un badge por tarea Fargate: el ALB reparte las peticiones y cada tarea tiene su propio circuito. */
export default function CircuitPanel({ circuits }) {
  const now = Date.now()
  const entries = Object.entries(circuits).filter(([, c]) => now - c.seenAt < STALE_MS)

  return (
    <div className="circuit-panel">
      <span className="muted small">Circuit Breaker · inventario legado</span>
      {entries.length === 0 && <StateBadge state={null} />}
      {entries.map(([host, c]) => (
        <div key={host} className="circuit-row">
          <code>{host}</code>
          <StateBadge state={c.state} />
          {c.failureRate >= 0 && <span className="muted small">{c.failureRate.toFixed(0)}% fallos</span>}
        </div>
      ))}
    </div>
  )
}
