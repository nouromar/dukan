-- Merged into 0009 (the refund_of_transaction_id column + FK + index)
-- and 0010 (void_sale with the p_refund_amount parameter). This file
-- is kept as a no-op so migration numbering stays stable across the
-- v2 schema break — the original incremental refund-add commit can
-- still be cross-referenced via git history.
--
-- See data-model-v2.md §7 (sanctioned-writers rule) and the void_sale
-- definition in 0010_posting_rpcs.sql.
select 1;
