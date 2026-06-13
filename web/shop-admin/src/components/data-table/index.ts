// Barrel export — import everything table-related from one path:
//   import { DataTable, EmptyState, type BulkAction } from "@/components/data-table";

export { DataTable, type DataTableProps } from "./data-table";
export { BulkActionBar, type BulkAction } from "./bulk-action-bar";
export { EmptyState, ErrorState, LoadingTable } from "./states";
