package com.example.outbox.web;

import com.example.outbox.domain.Order;
import com.example.outbox.domain.OrderService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;

@RestController
@RequestMapping("/orders")
@RequiredArgsConstructor
public class OrderController {

	private final OrderService orderService;

	@PostMapping
	public ResponseEntity<Order> create(@Valid @RequestBody CreateOrderRequest request) {
		Order order = orderService.createOrder(request.customerId(), request.amount());
		return ResponseEntity.ok(order);
	}

	public record CreateOrderRequest(
			@NotBlank String customerId,
			@NotNull @Positive BigDecimal amount
	) {}
}

