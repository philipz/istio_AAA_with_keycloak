package com.example.restservice;

import java.util.concurrent.atomic.AtomicLong;
import org.springframework.web.client.RestTemplate;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

@RestController
public class GreetingController {

	private final AtomicLong counter = new AtomicLong();

	
	private static final Logger logger = LoggerFactory.getLogger(GreetingController.class);

	@GetMapping("/greeting")
	public Greeting greeting() {
		
		RestTemplate restTemplate = new RestTemplate();
		try {
			ResponseEntity<List<Book>> response = restTemplate.exchange(
				"http://book-info.172.19.0.6.nip.io/getbooks",
				HttpMethod.GET,
				null,
				new ParameterizedTypeReference<List<Book>>() {}
			);
			
			List<Book> books = response.getBody();
			int bookCount = books != null ? books.size() : 0;
			
			logger.info(String.format("Retrieved %d books from the API", bookCount));
			
			if (bookCount > 0) {
				logger.info(String.format("%s books available.", bookCount));
				return new Greeting(counter.incrementAndGet(), String.format("Hello, dear Member! We have %d books available for you.", bookCount));
			} else {
				logger.info(String.format("No books available."));
				return new Greeting(counter.incrementAndGet(), String.format("Hello, no books available for you."));
			}
		} catch (Exception e) {
			logger.error("Error calling book API: " + e.getMessage(), e);
			return new Greeting(counter.incrementAndGet(), String.format("Sorry, we couldn't retrieve book information at the moment."));
		}
	}
}