package com.example.restservice;


import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class WelcomeController {

	@GetMapping("/")
	public String welcome() {
		return "welcome v2";
	}

}