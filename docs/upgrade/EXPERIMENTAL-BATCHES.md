# Large selections: planner implemented, execution disabled

`ExperimentalBatchPlan` partitions 0–4096 eligible entries into ranges of at most 128; tests verify exact coverage, boundaries and invalid caps. The shipping selection and Quick Share engine retain the 128-file limit.

A queue executor is deliberately not exposed in this candidate. Each batch would create a separate encrypted session and receiver approval. The existing outgoing lifecycle has one selected-source snapshot, security-scope ownership, progress samples and one completion cleanup. Automatically replacing that snapshot or clearing selection between batches could invalidate access, erase a later job, or retry already-sent files. Byte-level resumption is not implemented by the current protocol.

Execution remains `false` until a dedicated queue owns immutable per-batch file snapshots and scoped access, has a full-job cancellation contract, and passes real-receiver tests for repeated approvals, discovery ID changes, backgrounding, source mutation, partial failures and per-batch retry. Automated planner tests are not evidence that multi-session transfers work on phones.

This is experimental planning support, not a claim of usable large-batch execution. Users should select at most 128 files per transfer in this candidate.
