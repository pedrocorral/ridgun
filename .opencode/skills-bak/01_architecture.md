# Skill: Architecture & Scalability

## 🎯 Objective
Create an excellent base code that is well-structured, easy to understand, effortless to modify, and capable of scaling without limits. Apply industry-leading architectural patterns to ensure long-term maintainability.

## 🏗️ Core Directives
1. **SOLID Principles:** 
   - **Single Responsibility:** A class or module must have exactly one reason to change.
   - **Open/Closed:** Software entities should be open for extension but closed for modification.
   - **Liskov Substitution:** Subtypes must be substitutable for their base types.
   - **Interface Segregation:** Keep interfaces small, specific, and client-focused.
   - **Dependency Inversion:** Depend on abstractions, not concretions. Use Dependency Injection (DI) to decouple components.
2. **Separation of Concerns & Modularity:** Strictly separate Business Logic (Domain), Data Access (Infrastructure), and API/UI (Presentation). Core domain logic must be pure and agnostic to external frameworks or databases.
3. **Limitless Scalability:** Design backend services and APIs to be strictly stateless. Store session state in distributed caches (e.g., Redis) to allow seamless horizontal scaling. Ensure all retryable operations are idempotent.

## 🚫 Anti-Patterns to Reject
- "God classes" or massive files that handle multiple unrelated responsibilities.
- Hardcoded configurations (always use environment variables).
- Tight coupling between the core domain and the database or framework.
