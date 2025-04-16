# Testing Strategy

This document outlines the testing strategy for the Hyper Authenticator application, ensuring code quality, reliability, and maintainability across its different layers based on the Clean Architecture principles.

## 1. Testing Pyramid

We aim to follow the principles of the testing pyramid, focusing heavily on unit tests, followed by widget tests, and a smaller number of integration/end-to-end tests.

```
      /\
     /  \ Integration / E2E Tests
    /____\
   /      \ Widget Tests
  /________\
 /          \ Unit Tests
/____________\
```

## 2. Testing Levels & Scope

### 2.1. Unit Tests (`test/` directory)

*   **Focus:** Testing individual functions, methods, or classes in isolation. Primarily targets the Data and Domain layers, and BLoCs/Cubits in the Presentation layer.
*   **Scope:**
    *   **Domain Layer:**
        *   **UseCases:** Verify that each UseCase correctly orchestrates interactions with mock Repositories and returns the expected `Either<Failure, SuccessType>`. Test different scenarios (success, specific failures).
        *   **Entities:** Test any logic within entities (if any, usually minimal).
    *   **Data Layer:**
        *   **Repositories:** Verify that Repository implementations correctly call methods on mock Data Sources (local and remote) and handle potential exceptions by returning appropriate `Failure` types. Test data mapping logic (DTOs to/from Entities).
        *   **Data Sources:** Test interactions with external dependencies (like `FlutterSecureStorage`, `SharedPreferences`, Supabase client libraries) using mocks. Verify correct data fetching, saving, and error handling.
        *   **Models/DTOs:** Test serialization/deserialization logic (`fromJson`, `toJson`) if applicable.
    *   **Presentation Layer (BLoCs/Cubits):**
        *   Use `bloc_test` package.
        *   Verify that BLoCs/Cubits emit the correct sequence of states in response to specific events/method calls.
        *   Mock UseCases and other dependencies. Test state transitions for success and failure scenarios.
    *   **Core/Utils:** Test utility functions, validators, helper classes.
*   **Tools:** `test`, `mockito` (or `mocktail`), `bloc_test`, `dartz`.

### 2.2. Widget Tests (`test/` directory, often in feature subfolders)

*   **Focus:** Testing individual Flutter Widgets or groups of related widgets (e.g., a single screen or a complex component) in isolation from the full application. Verifies UI rendering, user interaction, and integration with BLoCs/Providers.
*   **Scope:**
    *   **Presentation Layer (UI):**
        *   Verify that widgets render correctly based on different states emitted by mock BLoCs/Cubits.
        *   Test user interactions (tapping buttons, entering text) and verify that the correct events are dispatched to the BLoC/Cubit.
        *   Test navigation logic triggered by widget interactions (using mock `GoRouter`).
        *   Verify correct display of data provided by BLoCs/Providers.
*   **Tools:** `flutter_test`, `mockito` (or `mocktail`), `bloc_test`, `provider`.

### 2.3. Integration Tests (`integration_test/` directory)

*   **Focus:** Testing the integration between different parts of the application, including UI, state management, business logic, and potentially external services (though often mocked). Verifies complete user flows.
*   **Scope:**
    *   Test critical user journeys, such as:
        *   Adding a new account via QR scan.
        *   Generating and displaying TOTP codes.
        *   User login/logout flow.
        *   App lock authentication flow.
        *   Data synchronization (upload/download - potentially mocking the network layer).
        *   Deleting an account.
    *   These tests run on a real device or emulator.
*   **Tools:** `integration_test`, `flutter_driver` (optional, for more complex E2E), `mockito` (for mocking external services if needed).

## 3. Mocking Strategy

*   **Unit Tests:** Mock all external dependencies (Repositories, Data Sources, external packages like `http`, `local_auth`, `otp`).
*   **Widget Tests:** Mock BLoCs/Cubits, UseCases, and navigation (`GoRouter`). Provide mock data via Providers if necessary.
*   **Integration Tests:** Mock external network calls (Supabase) or use a dedicated test environment if available and feasible. Avoid mocking internal components unless absolutely necessary.

## 4. Code Coverage

While aiming for high code coverage is beneficial, the primary goal is to write meaningful tests that cover critical paths and edge cases. Coverage reports (generated using `flutter test --coverage`) will be used as an indicator but not the sole metric for test quality. Focus will be on ensuring key logic in Domain, Data, and BLoCs is well-tested.

## 5. Continuous Integration (CI)

A CI pipeline (e.g., using GitHub Actions) should be set up to automatically run all unit and widget tests on every push or pull request to ensure regressions are caught early. Integration tests might be run less frequently (e.g., nightly or before releases) due to their longer execution time.