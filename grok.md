Here is a complete, practical **Spring Boot + PostgreSQL + Debezium Outbox Event Router** example using the **Transactional Outbox pattern** with **Kafka Connect** (Debezium runs outside the Spring Boot app as a separate connector).

This is the most common production-style setup in 2025–2026.

### 1. Project Structure Overview

```
transactional-outbox-demo/
├── src/main/java/com/example/outbox/
│   ├── OutboxApplication.java
│   ├── domain/
│   │   ├── Order.java
│   │   ├── OrderRepository.java
│   │   └── OrderService.java
│   ├── outbox/
│   │   ├── OutboxEvent.java
│   │   └── OutboxRepository.java
│   └── web/
│       └── OrderController.java
├── src/main/resources/
│   └── application.yml
├── pom.xml
└── docker-compose.yml   (Postgres + Kafka + Zookeeper + Kafka Connect)
```

### 2. pom.xml (key dependencies – Spring Boot 3.3+ / 3.4)

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <scope>runtime</scope>
    </dependency>
    <!-- Optional: Lombok -->
    <dependency>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <optional>true</optional>
    </dependency>
</dependencies>
```

### 3. application.yml

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/outboxdb
    username: postgres
    password: postgres
  jpa:
    hibernate:
      ddl-auto: none           # use Flyway / Liquibase in real projects
    show-sql: true
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
server:
  port: 8080
```

### 4. Domain & Outbox Entities

**Order.java** (JPA entity)

```java
import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;

@Entity
@Table(name = "orders")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class Order {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String customerId;
    private BigDecimal amount;
    private String status = "PENDING";
}
```

**OutboxEvent.java** (the outbox table)

```java
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Entity
@Table(name = "outbox")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class OutboxEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private String id;

    @Column(name = "aggregatetype")
    private String aggregateType;       // e.g. "Order"

    @Column(name = "aggregateid")
    private String aggregateId;

    private String type;                // e.g. "OrderCreated"

    @Column(columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private String payload;             // JSON string

    private OffsetDateTime timestamp = OffsetDateTime.now();
}
```

### 5. Repositories

```java
public interface OrderRepository extends JpaRepository<Order, Long> {}
public interface OutboxRepository extends JpaRepository<OutboxEvent, String> {}
```

### 6. Service – Business Logic + Outbox Write (atomic)

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepo;
    private final OutboxRepository outboxRepo;

    @Transactional
    public Order createOrder(String customerId, BigDecimal amount) {
        // 1. Business change
        Order order = new Order();
        order.setCustomerId(customerId);
        order.setAmount(amount);
        order.setStatus("CREATED");
        order = orderRepo.save(order);

        // 2. Write event to outbox – same transaction
        OutboxEvent event = new OutboxEvent();
        event.setAggregateType("Order");
        event.setAggregateId(order.getId().toString());
        event.setType("OrderCreated");

        // Simple JSON payload (in real apps → use Jackson/ObjectMapper or Avro)
        String payload = """
                {
                  "orderId": %d,
                  "customerId": "%s",
                  "amount": %s,
                  "status": "%s",
                  "createdAt": "%s"
                }
                """.formatted(
                order.getId(),
                customerId,
                amount,
                order.getStatus(),
                OffsetDateTime.now()
        );
        event.setPayload(payload);

        outboxRepo.save(event);

        return order;
    }
}
```

### 7. REST Controller

```java
@RestController
@RequestMapping("/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @PostMapping
    public ResponseEntity<Order> create(
            @RequestBody CreateOrderRequest request) {
        Order order = orderService.createOrder(
                request.customerId(),
                request.amount()
        );
        return ResponseEntity.ok(order);
    }

    record CreateOrderRequest(String customerId, BigDecimal amount) {}
}
```

### 8. Database Setup (run via Flyway or manually)

```sql
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    customer_id VARCHAR(255),
    amount DECIMAL(12,2),
    status VARCHAR(50) DEFAULT 'PENDING'
);

CREATE TABLE outbox (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregatetype VARCHAR(255) NOT NULL,
    aggregateid   VARCHAR(255) NOT NULL,
    type          VARCHAR(255) NOT NULL,
    payload       JSONB NOT NULL,
    timestamp     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_outbox_timestamp ON outbox(timestamp);
```

### 9. Debezium Connector Config (Kafka Connect)

Create this via REST (http://localhost:8083/connectors) or file-based:

```json
{
  "name": "outbox-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "postgres",
    "database.password": "postgres",
    "database.dbname": "outboxdb",
    "database.server.name": "dbserver1",
    "plugin.name": "pgoutput",
    "slot.name": "outbox_slot",
    "table.include.list": "public.outbox",
    "tombstones.on.delete": "false",
    "transforms": "outbox",
    "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
    "transforms.outbox.table.field.event.id": "id",
    "transforms.outbox.table.field.event.payload": "payload",
    "transforms.outbox.table.field.event.type": "type",
    "transforms.outbox.table.field.event.timestamp": "timestamp",
    "transforms.outbox.table.field.event.key": "aggregateid",
    "transforms.outbox.route.topic.regex": ".*",
    "transforms.outbox.route.topic.pattern": "events.order.${routedByValue:aggregatetype}.${routedByValue:type}",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
  }
}
```

### 10. docker-compose.yml (quick start)

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: outboxdb
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
    ports:
      - "2181:2181"

  kafka:
    image: confluentinc/cp-kafka:7.6.0
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,PLAINTEXT_HOST://localhost:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT

  connect:
    image: confluentinc/cp-kafka-connect:7.6.0
    depends_on:
      - kafka
      - postgres
    ports:
      - "8083:8083"
    environment:
      CONNECT_BOOTSTRAP_SERVERS: kafka:9092
      CONNECT_REST_PORT: 8083
      CONNECT_GROUP_ID: connect-cluster
      CONNECT_CONFIG_STORAGE_TOPIC: connect-configs
      CONNECT_OFFSET_STORAGE_TOPIC: connect-offsets
      CONNECT_STATUS_STORAGE_TOPIC: connect-status
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_PLUGIN_PATH: /usr/share/java,/usr/share/confluent-hub-components
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1

volumes:
  pgdata:
```

### How to Run

1. `docker compose up -d`
2. Create tables (manually or via Flyway)
3. Register connector: `curl -X POST -H "Content-Type: application/json" --data @connector.json http://localhost:8083/connectors`
4. Start Spring Boot: `./mvnw spring-boot:run`
5. POST to `http://localhost:8080/orders` → see event in Kafka topic `events.order.Order.OrderCreated`

This gives **atomicity** (DB + outbox in one tx), **reliability** (Debezium tails WAL), and **exactly-once** potential (with idempotent consumers + deduplication).

Many real projects use **Quarkus** + `quarkus-debezium-outbox` for even simpler integration, but the above is pure Spring Boot + Debezium.

Let me know if you want cleanup job, Avro/Schema Registry, idempotency on consumer side, or Quarkus variant!
