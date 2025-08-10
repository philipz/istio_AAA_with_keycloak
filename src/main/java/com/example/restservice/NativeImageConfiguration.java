package com.example.restservice;

import org.springframework.aot.hint.MemberCategory;
import org.springframework.aot.hint.RuntimeHints;
import org.springframework.aot.hint.RuntimeHintsRegistrar;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.ImportRuntimeHints;

@Configuration
@ImportRuntimeHints(NativeImageConfiguration.RestServiceRuntimeHints.class)
public class NativeImageConfiguration {

    static class RestServiceRuntimeHints implements RuntimeHintsRegistrar {
        @Override
        public void registerHints(RuntimeHints hints, ClassLoader classLoader) {
            // Register reflection hints for model classes
            hints.reflection()
                    .registerType(Book.class, MemberCategory.values())
                    .registerType(Greeting.class, MemberCategory.values());
            
            // Register resource hints if needed
            hints.resources().registerPattern("application*.properties");
            hints.resources().registerPattern("static/**");
            
            // Register serialization hints for JSON
            hints.serialization()
                    .registerType(org.springframework.aot.hint.TypeReference.of(Book.class))
                    .registerType(org.springframework.aot.hint.TypeReference.of(Greeting.class));
        }
    }
}