# ---- Build React (Vite) ----
FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci || npm install
COPY . .
RUN npm run build

# ---- Nginx: estaticos + reverse proxy /api -> API Gateway ----
FROM nginx:1.27-alpine
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
# Valor por defecto para docker-compose local; en ECS lo sobreescribe la Task Definition
ENV API_UPSTREAM=http://backend:8080
EXPOSE 80
