# Skill: Data Persistence & State Management

## 🎯 Objective
Ensure impeccable data integrity, optimized access patterns, and safe schema evolution. Treat the database as the foundational source of truth.

## 💾 Core Directives
1. **ACID Transactions:** Group multiple database write operations that belong to a single logical action inside a Transaction. If one step fails, the entire transaction MUST rollback.
2. **Immutable Migrations:** Database schemas must be version-controlled via forward-rolling migration scripts. Migrations must be backward-compatible.
3. **Idempotency:** Ensure retryable operations (like processing payments or webhooks) are strictly idempotent. Repeated execution with the same parameters must yield the same result safely.
4. **Stateless APIs:** Keep the application servers stateless. Store session and ephemeral state in external specialized stores (like Redis) to allow horizontal scaling without state corruption.

## 🚫 Anti-Patterns to Reject
- Modifying production schemas manually without automated migration scripts.
- Relying on application-level locks for data integrity instead of database-level constraints (e.g., unique constraints, foreign keys).
