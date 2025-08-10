package com.example.restservice;

import java.util.concurrent.atomic.AtomicLong;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

@RestController
public class GreetingController {

	private final AtomicLong counter = new AtomicLong();
	private static final Logger logger = LoggerFactory.getLogger(GreetingController.class);

	@Autowired
	private OAuth2AuthorizedClientManager authorizedClientManager;

	@Autowired
	private RestTemplate restTemplate;

	@Value("${book-info.service.url}")
	private String bookInfoServiceUrl;

	@GetMapping("/greeting")
	public Greeting greeting() {
		try {
			// Get OAuth2 access token using client credentials
			OAuth2AuthorizeRequest authorizeRequest = OAuth2AuthorizeRequest
				.withClientRegistrationId("keycloak")
				.principal("greeting-service")
				.build();

			OAuth2AuthorizedClient authorizedClient = authorizedClientManager.authorize(authorizeRequest);
			
			if (authorizedClient == null) {
				logger.error("Failed to authorize OAuth2 client");
				return new Greeting(counter.incrementAndGet(), "Authentication failed - could not retrieve book information.");
			}

			String accessToken = authorizedClient.getAccessToken().getTokenValue();
			logger.info("Successfully obtained OAuth2 access token");

			// Create HTTP headers with Bearer token
			HttpHeaders headers = new HttpHeaders();
			headers.setBearerAuth(accessToken);
			HttpEntity<?> entity = new HttpEntity<>(headers);

			// Make authenticated request to book-info service
			ResponseEntity<List<Book>> response = restTemplate.exchange(
				bookInfoServiceUrl + "/getbooks",
				HttpMethod.GET,
				entity,
				new ParameterizedTypeReference<List<Book>>() {}
			);
			
			List<Book> books = response.getBody();
			int bookCount = books != null ? books.size() : 0;
			
			logger.info("Retrieved {} books from the authenticated API call", bookCount);
			
			if (bookCount > 0) {
				return new Greeting(counter.incrementAndGet(), 
					String.format("Hello, authenticated Member! We have %d books available for you.", bookCount));
			} else {
				return new Greeting(counter.incrementAndGet(), 
					"Hello, authenticated Member! No books are currently available.");
			}
		} catch (Exception e) {
			logger.error("Error calling book API with OAuth2 authentication: " + e.getMessage(), e);
			return new Greeting(counter.incrementAndGet(), 
				"Sorry, we couldn't retrieve book information at the moment. Authentication or service error occurred.");
		}
	}
}