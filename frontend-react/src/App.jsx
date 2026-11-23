import { useCallback, useEffect, useState } from 'react'
import { createOrder, getCircuit, getOrders, getProducts } from './api.js'
import CircuitPanel from './components/CircuitPanel.jsx'
import OrdersTable from './components/OrdersTable.jsx'
import OrderResult from './components/OrderResult.jsx'

export default function App() {
  const [products, setProducts] = useState([])
  const [orders, setOrders] = useState([])
  // Cada tarea Fargate tiene su propio Circuit Breaker: guardamos el ultimo estado visto por tarea.
  const [circuits, setCircuits] = useState({})
  const [form, setForm] = useState({ productId: 1, quantity: 1, customerEmail: 'user@uce.edu.ec' })
  const [results, setResults] = useState([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)

  const rememberCircuit = useCallback((host, state, extra = {}) => {
    if (!host) return
    setCircuits((prev) => ({ ...prev, [host]: { ...prev[host], ...extra, state, seenAt: Date.now() } }))
  }, [])

  const refreshOrders = useCallback(() => getOrders().then(setOrders).catch(() => {}), [])

  useEffect(() => {
    getProducts().then(setProducts).catch((e) => setError(`No se pudo cargar el catalogo: ${e.message}`))
    refreshOrders()
  }, [refreshOrders])

  useEffect(() => {
    const poll = () =>
      getCircuit()
        .then((c) => rememberCircuit(c.servedBy, c.state, { failureRate: c.failureRate, bufferedCalls: c.bufferedCalls }))
        .catch(() => {})
    poll()
    const id = setInterval(poll, 1500)
    return () => clearInterval(id)
  }, [rememberCircuit])

  const sendOrders = async (count) => {
    setBusy(true)
    setError(null)
    const batch = []
    for (let i = 0; i < count; i++) {
      const started = performance.now()
      try {
        const order = await createOrder({ ...form, productId: Number(form.productId), quantity: Number(form.quantity) })
        const roundTripMs = Math.round(performance.now() - started)
        batch.push({ ...order, roundTripMs })
        rememberCircuit(order.servedBy, order.circuitState)
        setResults([...batch].reverse())
      } catch (e) {
        setError(e.message)
        break
      }
    }
    setBusy(false)
    refreshOrders()
  }

  return (
    <div className="page">
      <header className="topbar">
        <div>
          <h1>MiniStore Express</h1>
          <p className="muted">Portal de ordenes · React + Nginx → API Gateway → ALB → ECS Fargate</p>
        </div>
        <CircuitPanel circuits={circuits} />
      </header>

      {error && <div className="alert">{error}</div>}

      <section>
        <h2>Catalogo</h2>
        <div className="grid">
          {products.map((p) => (
            <button
              key={p.id}
              type="button"
              className={`card product ${Number(form.productId) === p.id ? 'selected' : ''}`}
              onClick={() => setForm({ ...form, productId: p.id })}
            >
              <span className="product-id">#{p.id}</span>
              <strong>{p.name}</strong>
              <span className="muted small">{p.description}</span>
              <span className="price">${Number(p.price).toFixed(2)}</span>
            </button>
          ))}
        </div>
      </section>

      <section className="order-area">
        <form
          className="card form"
          onSubmit={(e) => {
            e.preventDefault()
            sendOrders(1)
          }}
        >
          <h2>Nueva orden</h2>
          <label>
            Cantidad
            <input type="number" min="1" max="100" value={form.quantity}
              onChange={(e) => setForm({ ...form, quantity: e.target.value })} />
          </label>
          <label>
            Email del cliente
            <input type="email" required value={form.customerEmail}
              onChange={(e) => setForm({ ...form, customerEmail: e.target.value })} />
          </label>
          <div className="actions">
            <button type="submit" className="primary" disabled={busy}>
              {busy ? 'Enviando…' : 'Crear orden'}
            </button>
            <button type="button" disabled={busy} onClick={() => sendOrders(6)}
              title="6 ordenes seguidas: ~3 llegan a cada tarea Fargate, suficiente para abrir ambos circuitos">
              Rafaga x6 (demo Circuit Breaker)
            </button>
          </div>
        </form>

        <OrderResult results={results} />
      </section>

      <section>
        <div className="section-head">
          <h2>Ultimas ordenes (RDS)</h2>
          <button type="button" onClick={refreshOrders}>Actualizar</button>
        </div>
        <OrdersTable orders={orders} />
      </section>
    </div>
  )
}
