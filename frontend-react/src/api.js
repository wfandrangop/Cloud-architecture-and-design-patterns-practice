// Todas las rutas son relativas: Nginx (AWS) o Vite (local) hacen proxy de /api/* -> backend.
async function request(path, options = {}) {
  const res = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  const text = await res.text()
  const body = text ? JSON.parse(text) : null
  if (!res.ok) {
    throw new Error(body?.detail ?? body?.message ?? `HTTP ${res.status}`)
  }
  return body
}

export const getProducts = () => request('/api/products')
export const getOrders = () => request('/api/orders')
export const getCircuit = () => request('/api/orders/health-circuit')
export const createOrder = (order) =>
  request('/api/orders', { method: 'POST', body: JSON.stringify(order) })
