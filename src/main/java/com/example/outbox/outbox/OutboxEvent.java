package com.example.outbox.outbox;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "outbox")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class OutboxEvent {

	@Id
	@GeneratedValue(strategy = GenerationType.UUID)
	private UUID id;

	@Column(name = "aggregatetype", nullable = false)
	private String aggregateType; // e.g. "Order"

	@Column(name = "aggregateid", nullable = false)
	private String aggregateId;

	@Column(nullable = false)
	private String type; // e.g. "OrderCreated"

	/**
	 * Stored as JSONB in Postgres. Keep as a JSON string for Debezium outbox router.
	 */
	@Column(nullable = false)
	@JdbcTypeCode(SqlTypes.JSON)
	private String payload;

	@Column(name = "timestamp", nullable = false)
	private OffsetDateTime timestamp = OffsetDateTime.now();
}

