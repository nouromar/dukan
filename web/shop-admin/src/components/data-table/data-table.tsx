// Generic DataTable used by every list module (sales history,
// products, parties, audit log, ...). Built on TanStack Table v8 for
// the sorting/selection/filtering primitives, rendered through
// shadcn's Table for consistent visual treatment.
//
// Capabilities:
//   - Column definitions via TanStack ColumnDef<T>
//   - Click-row navigation (set onRowClick)
//   - Row selection + BulkActionBar (set bulkActions; selection
//     column is auto-injected)
//   - Empty / loading / error states delegated to states.tsx
//
// Not in scope here:
//   - Server-side pagination — add when a real module needs it; today
//     every v1 list fits comfortably in `historyPageLimit` rows.
//   - Column visibility menu, column resizing — these belong in #271's
//     follow-ons once a real use case demands them.

"use client";

import { useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import {
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type Row,
  type RowSelectionState,
  type SortingState,
} from "@tanstack/react-table";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Checkbox } from "@/components/ui/checkbox";
import { cn } from "@/lib/utils";
import { BulkActionBar, type BulkAction } from "./bulk-action-bar";
import { EmptyState, ErrorState, LoadingTable } from "./states";

export type DataTableProps<T> = {
  /** Column definitions. */
  columns: ColumnDef<T, unknown>[];
  /** Row data. `undefined` triggers loading state. */
  data: T[] | undefined;
  /** Non-null switches the table to the error state. */
  error?: { message?: string } | null;
  /** Optional empty-state override (title + description + action). */
  empty?: React.ReactNode;
  /** Called when a row is clicked. Selection clicks don't trigger it. */
  onRowClick?: (row: T) => void;
  /**
   * Per-row stable id. Required when bulkActions is set — TanStack
   * needs it to track selection across re-sort/re-filter.
   */
  getRowId?: (row: T, index: number) => string;
  /** When non-empty, a checkbox column is injected and BulkActionBar renders. */
  bulkActions?: (selectedRows: T[]) => BulkAction[];
};

export function DataTable<T>({
  columns,
  data,
  error,
  empty,
  onRowClick,
  getRowId,
  bulkActions,
}: DataTableProps<T>) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const [rowSelection, setRowSelection] = useState<RowSelectionState>({});
  const t = useTranslations("table.selection");

  const enableSelection = !!bulkActions;

  const finalColumns = useMemo<ColumnDef<T, unknown>[]>(() => {
    if (!enableSelection) return columns;
    const selectionColumn: ColumnDef<T, unknown> = {
      id: "__select",
      enableSorting: false,
      size: 36,
      header: ({ table }) => (
        <Checkbox
          checked={table.getIsAllPageRowsSelected()}
          indeterminate={
            !table.getIsAllPageRowsSelected() &&
            table.getIsSomePageRowsSelected()
          }
          onCheckedChange={(value) =>
            table.toggleAllPageRowsSelected(value)
          }
          aria-label={t("selectAll")}
        />
      ),
      cell: ({ row }) => (
        <Checkbox
          checked={row.getIsSelected()}
          onCheckedChange={(value) => row.toggleSelected(value)}
          aria-label={t("selectRow")}
          // Stop propagation so checkbox clicks never trigger onRowClick.
          onClick={(e) => e.stopPropagation()}
        />
      ),
    };
    return [selectionColumn, ...columns];
  }, [columns, enableSelection, t]);

  const table = useReactTable({
    data: data ?? [],
    columns: finalColumns,
    state: { sorting, rowSelection },
    onSortingChange: setSorting,
    onRowSelectionChange: setRowSelection,
    enableRowSelection: enableSelection,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getRowId: getRowId ? (row, index) => getRowId(row, index) : undefined,
  });

  // Order matters: error > loading > empty > table. Surfacing an error
  // even when stale data is present prevents the user from acting on
  // a known-incomplete view.
  if (error) {
    return (
      <ErrorState description={error.message} />
    );
  }
  if (data === undefined) {
    return <LoadingTable columns={finalColumns.length} />;
  }
  if (data.length === 0) {
    return <>{empty ?? <EmptyState />}</>;
  }

  const selectedRows = table
    .getSelectedRowModel()
    .rows.map((r: Row<T>) => r.original);
  const actions = bulkActions ? bulkActions(selectedRows) : [];

  return (
    <div className="space-y-0">
      <div className="overflow-hidden rounded-lg border">
        <Table>
          <TableHeader className="bg-muted/30">
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => {
                  const canSort = header.column.getCanSort();
                  return (
                    <TableHead
                      key={header.id}
                      style={
                        header.getSize() && header.getSize() !== 150
                          ? { width: header.getSize() }
                          : undefined
                      }
                      className={cn(
                        "text-xs font-medium uppercase tracking-wide text-muted-foreground",
                        canSort && "cursor-pointer select-none",
                      )}
                      onClick={
                        canSort
                          ? header.column.getToggleSortingHandler()
                          : undefined
                      }
                    >
                      {header.isPlaceholder
                        ? null
                        : flexRender(
                            header.column.columnDef.header,
                            header.getContext(),
                          )}
                      {canSort && header.column.getIsSorted()
                        ? header.column.getIsSorted() === "desc"
                          ? " ↓"
                          : " ↑"
                        : null}
                    </TableHead>
                  );
                })}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {table.getRowModel().rows.map((row) => (
              <TableRow
                key={row.id}
                data-state={row.getIsSelected() ? "selected" : undefined}
                className={cn(
                  onRowClick && "cursor-pointer hover:bg-muted/50",
                )}
                onClick={
                  onRowClick ? () => onRowClick(row.original) : undefined
                }
              >
                {row.getVisibleCells().map((cell) => (
                  <TableCell key={cell.id}>
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </TableCell>
                ))}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <BulkActionBar
        selectedCount={selectedRows.length}
        actions={actions}
        onClear={() => setRowSelection({})}
      />
    </div>
  );
}
