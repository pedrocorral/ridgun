# Skill: Performance & Optimization

## 🎯 Objective
Write code that is blazingly fast, highly efficient with system resources (CPU, Memory, I/O), and scalable. Treat performance as a core engineering feature.

## ⚡ Core Directives
1. **Algorithmic Efficiency (Big O):** ALWAYS select the optimal data structure. Use Hash Maps/Sets (O(1) lookups) instead of nested arrays (O(N²)) for searches or deduplication.
2. **Lazy Evaluation & Streaming:** NEVER load massive datasets or large files entirely into RAM. Use generators, iterators, and streams to process data in chunks.
3. **Strategic Caching:** Implement aggressive caching (e.g., Redis, Memcached) for computationally expensive or frequently accessed static data, with explicit TTL (Time-To-Live) and invalidation strategies.
4. **Database Optimization:** AVOID the N+1 query problem. Eagerly fetch related data, utilize database indexing on frequently queried columns, and paginate large results.

## 🚫 Anti-Patterns to Reject
- Premature Optimization: Sacrificing readability for micro-optimizations before identifying the actual bottleneck via profiling.
- Performing synchronous I/O operations inside high-traffic loops.
