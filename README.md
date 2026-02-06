# Transactional Outbox Pattern Demo (Spring Boot + Postgres + Debezium)

This project demonstrates the **Transactional Outbox pattern** using:

- **Spring Boot** (writes business data + outbox event atomically in one DB transaction)
- **PostgreSQL** (stores `orders` + `outbox` tables)
- **Debezium Outbox Event Router** (runs in **Kafka Connect** outside the app; tails Postgres WAL and publishes outbox events to Kafka)
- SMT (Single Message Transform) rewrites each change event into an outbox-style message (topic routing, key/payload mapping, headers, timestamps).

## NOTE: SMT = Single Message Transform in Kafka Connect.
It’s a lightweight transformation applied to each record as it moves through Connect. In this project, the Debezium Outbox Event Router is an SMT that rewrites the Debezium CDC record into an event-style message (topic routing, key/payload mapping, headers, timestamps).

The Spring Boot app **does not publish to Kafka directly**. It only inserts into the `outbox` table in the same transaction as the business write.

## Project layout

Key packages:

- `com.example.outbox.domain`
  - `Order`, `OrderRepository`, `OrderService`
- `com.example.outbox.outbox`
  - `OutboxEvent`, `OutboxRepository`
- `com.example.outbox.web`
  - `OrderController`

## Prerequisites

- Java (project uses Gradle toolchains; see `build.gradle`)
- Docker + Docker Compose

## Run it

### 1) Start Postgres + Kafka + Kafka Connect

```bash
docker compose up -d
```

### 2) Start the Spring Boot app

The app will run Flyway migration `V1__init.sql` on startup against Postgres.

```bash
./gradlew bootRun
```

App listens on `http://localhost:8080`.

### 3) Register the Debezium connector

This repository includes a ready-to-use Kafka Connect config in `connector.json`.

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  --data @connector.json \
  http://localhost:8083/connectors
```

Kafka Connect listens on `http://localhost:8083`.

## Use the API

### Create an order (writes `orders` + `outbox` in one transaction)

```bash
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"customerId":"cust-123","amount":12.34}'
```

This will:

- Insert a row into `orders`
- Insert an `OrderCreated` event into `outbox` (same DB transaction)

## Database schema

Managed by Flyway:

- `src/main/resources/db/migration/V1__init.sql`

Tables:

- `orders`
- `outbox` (Debezium outbox router source table)

## Notes / troubleshooting

- **Kafka Connect plugin**: The `docker-compose.yml` starts Kafka Connect, but it does not automatically install Debezium connector plugins.
  - If your Connect image doesn’t already include Debezium, you’ll need to add the Debezium Postgres connector + outbox SMT to the Connect plugin path.
- **Outbox timestamp field**: `outbox.timestamp` is a `TIMESTAMP`, and the connector config sets `"transforms.outbox.table.field.event.timestamp": "timestamp"`.
  - If you change that column to `BIGINT`, the outbox SMT will fail because it expects a logical timestamp or epoch millis with the expected schema.
  - If the SMT crashes with a timestamp type error, either revert the column to `TIMESTAMP` or remove the SMT timestamp mapping.
- **Tests** run with an in-memory H2 DB via `src/test/resources/application-test.yml`.
