package com.example.restservice;

public record Book(
    long isbn,
    String title,
    String synopsis,
    String authorname,
    double price
) {}
