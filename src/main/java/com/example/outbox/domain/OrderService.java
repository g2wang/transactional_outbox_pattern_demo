package com.example.outbox.domain;

import com.example.outbox.outbox.OutboxEvent;
import com.example.outbox.outbox.OutboxRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Service
@RequiredArgsConstructor
public class OrderService {

	private final OrderRepository orderRepo;
	private final OutboxRepository outboxRepo;

	@Transactional
	public Order createOrder(String customerId, BigDecimal amount) {
		// 1) Business change
		Order order = new Order();
		order.setCustomerId(customerId);
		order.setAmount(amount);
		order.setStatus("CREATED");
		order = orderRepo.save(order);

		// 2) Outbox insert (same transaction)
		OutboxEvent event = new OutboxEvent();
		event.setAggregateType("Order");
		event.setAggregateId(order.getId().toString());
		event.setType("OrderCreated");

		// Simple JSON payload (Debezium outbox router expects JSON string in `payload`)
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

