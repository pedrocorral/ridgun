//! Lexical Region Memory Engine — O(1) bump arenas without tracing GC.
//! Implements Section 7 and Section 12.2 of `docs/etc/next_gen_architecture.md`.

use crate::vm::Value;

/// Default capacity (in bytes) of a lexical function region.
pub const DEFAULT_REGION_BYTES: usize = 64 * 1024;

/// Error returned when a quota-bounded region exceeds its memory limit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RegionError {
    OutOfMemory { requested: usize, limit: usize },
    SubcallParentResetForbidden,
}

/// A lexical bump-allocated memory region bound to a function or worker scope.
#[derive(Debug, Clone)]
pub struct Region {
    pub id: usize,
    pub parent_id: Option<usize>,
    buffer: Vec<u8>,
    cursor: usize,
    limit: usize,
    values: Vec<Value>,
}

impl Region {
    /// Create a new root or child lexical region with the default capacity.
    pub fn new(id: usize, parent_id: Option<usize>) -> Self {
        Self::with_quota(id, parent_id, DEFAULT_REGION_BYTES)
    }

    /// Create a quota-bounded lexical region with a hard byte limit.
    pub fn with_quota(id: usize, parent_id: Option<usize>, limit: usize) -> Self {
        Region {
            id,
            parent_id,
            buffer: vec![0u8; limit],
            cursor: 0,
            limit,
            values: Vec::new(),
        }
    }

    /// Return the current byte cursor watermark and value slot watermark.
    pub fn watermark(&self) -> (usize, usize) {
        (self.cursor, self.values.len())
    }

    /// Current bytes allocated in this region.
    pub fn used_bytes(&self) -> usize {
        self.cursor
    }

    /// Maximum quota in bytes for this region.
    pub fn quota_bytes(&self) -> usize {
        self.limit
    }

    /// Dynamically update the hard byte quota for this region (`with region limit`).
    pub fn set_quota(&mut self, limit: usize) {
        self.limit = limit;
        if self.buffer.len() < limit {
            self.buffer.resize(limit, 0);
        }
    }

    /// Return a slice of the currently allocated raw bytes in this region's linear buffer.
    pub fn raw_bytes(&self) -> &[u8] {
        &self.buffer[..self.cursor]
    }

    /// Bump-allocate `size` bytes aligned to 8 bytes inside this region.
    pub fn alloc_bytes(&mut self, size: usize) -> Result<usize, RegionError> {
        let aligned = (size + 7) & !7;
        let next_cursor = self.cursor.saturating_add(aligned);
        if next_cursor > self.limit {
            return Err(RegionError::OutOfMemory {
                requested: aligned,
                limit: self.limit,
            });
        }
        let offset = self.cursor;
        self.cursor = next_cursor;
        Ok(offset)
    }

    /// Allocate a `Value` inside this region, charging its estimated byte footprint.
    pub fn alloc_value(&mut self, val: Value) -> Result<usize, RegionError> {
        let byte_cost = estimate_value_bytes(&val);
        self.alloc_bytes(byte_cost)?;
        let slot = self.values.len();
        self.values.push(val);
        Ok(slot)
    }

    /// Read a value stored at `slot` in this region.
    pub fn get_value(&self, slot: usize) -> Option<&Value> {
        self.values.get(slot)
    }

    /// Reset the region to a saved watermark in O(1) time.
    /// Forbids resetting if `caller_region_id` is a strict child of this region.
    pub fn reset_to(
        &mut self,
        watermark: (usize, usize),
        caller_region_id: usize,
    ) -> Result<(), RegionError> {
        if caller_region_id != self.id {
            return Err(RegionError::SubcallParentResetForbidden);
        }
        self.cursor = watermark.0.min(self.cursor);
        self.values.truncate(watermark.1);
        Ok(())
    }

    /// Reset the entire region in O(1) time on function exit.
    pub fn reset_all(&mut self) {
        self.cursor = 0;
        self.values.clear();
    }

    /// Evacuate (promote) a return value from this local region into `caller` region,
    /// then reset this local region in O(1) time (Section 7.2).
    pub fn evacuate_and_reset(
        &mut self,
        ret_val: &Value,
        caller: &mut Region,
    ) -> Result<usize, RegionError> {
        let promoted = ret_val.clone();
        let slot = caller.alloc_value(promoted)?;
        self.reset_all();
        Ok(slot)
    }
}

/// Tail-Call Region Ping-Pong arena pair (Section 7.4).
/// Guarantees O(1) bounded memory across infinite tail-recursive loops.
#[derive(Debug, Clone)]
pub struct PingPongArena {
    region_a: Region,
    region_b: Region,
    active_is_a: bool,
}

impl PingPongArena {
    /// Create a pair of alternating scratch regions with the given byte quota each.
    pub fn new(base_id: usize, quota: usize) -> Self {
        PingPongArena {
            region_a: Region::with_quota(base_id, None, quota),
            region_b: Region::with_quota(base_id + 1, None, quota),
            active_is_a: true,
        }
    }

    /// Mutable reference to the currently active iteration region.
    pub fn active_mut(&mut self) -> &mut Region {
        if self.active_is_a {
            &mut self.region_a
        } else {
            &mut self.region_b
        }
    }

    /// Perform a tail-call step: promote `next_args` into the standby region,
    /// reset the old active region in O(1), and swap roles.
    pub fn tail_call_step(&mut self, next_args: &[Value]) -> Result<Vec<Value>, RegionError> {
        let standby = if self.active_is_a {
            &mut self.region_b
        } else {
            &mut self.region_a
        };
        standby.reset_all();
        let mut promoted = Vec::with_capacity(next_args.len());
        for arg in next_args {
            let slot = standby.alloc_value(arg.clone())?;
            promoted.push(standby.get_value(slot).cloned().unwrap_or(Value::Unit));
        }
        if self.active_is_a {
            self.region_a.reset_all();
        } else {
            self.region_b.reset_all();
        }
        self.active_is_a = !self.active_is_a;
        Ok(promoted)
    }
}

/// Estimate the region byte footprint of a Ridgun `Value`.
pub fn estimate_value_bytes(val: &Value) -> usize {
    match val {
        Value::Int(_) | Value::Real(_) | Value::Char(_) | Value::Bool(_) | Value::Unit => 8,
        Value::MailboxRef(_) | Value::ThreadRef(_) | Value::ChannelRef(_) => 8,
        Value::Str(text) => 16 + text.len(),
        Value::List(items) | Value::Tuple(items) => {
            16 + items.iter().map(estimate_value_bytes).sum::<usize>()
        }
        Value::Adt(_, fields) => {
            16 + fields.iter().map(estimate_value_bytes).sum::<usize>()
        }
        Value::Tensor(shape, data) => {
            24 + shape.len() * 8 + data.len() * 8
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_region_bump_and_reset() {
        let mut reg = Region::new(1, None);
        let wm = reg.watermark();
        let slot = reg.alloc_value(Value::Int(42)).unwrap();
        assert_eq!(reg.get_value(slot), Some(&Value::Int(42)));
        assert!(reg.used_bytes() >= 8);

        reg.reset_to(wm, 1).unwrap();
        assert_eq!(reg.used_bytes(), 0);
    }

    #[test]
    fn test_subcall_cannot_reset_parent_region() {
        let mut parent = Region::new(1, None);
        parent.alloc_value(Value::Int(10)).unwrap();
        let err = parent.reset_to((0, 0), 2);
        assert_eq!(err, Err(RegionError::SubcallParentResetForbidden));
    }

    #[test]
    fn test_quota_bounded_region_oom() {
        let mut reg = Region::with_quota(1, None, 32);
        assert!(reg.alloc_bytes(16).is_ok());
        assert!(reg.alloc_bytes(16).is_ok());
        assert_eq!(
            reg.alloc_bytes(8),
            Err(RegionError::OutOfMemory { requested: 8, limit: 32 })
        );
    }

    #[test]
    fn test_evacuate_to_caller_and_reset_local() {
        let mut caller = Region::new(1, None);
        let mut local = Region::new(2, Some(1));
        local.alloc_value(Value::Str("temp".into())).unwrap();
        let ret = Value::List(vec![Value::Int(1), Value::Int(2)]);

        let slot = local.evacuate_and_reset(&ret, &mut caller).unwrap();
        assert_eq!(local.used_bytes(), 0);
        assert_eq!(caller.get_value(slot), Some(&ret));
    }

    #[test]
    fn test_ping_pong_tail_call_constant_memory() {
        let mut arena = PingPongArena::new(10, 256);
        for step in 0..100 {
            arena.active_mut().alloc_value(Value::Str("scratch".into())).unwrap();
            let promoted = arena.tail_call_step(&[Value::Int(step)]).unwrap();
            assert_eq!(promoted, vec![Value::Int(step)]);
            assert!(arena.active_mut().used_bytes() <= 16);
        }
    }
}
