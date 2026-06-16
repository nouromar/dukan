// Generic inline-edit primitive. Three variants — text, number, select
// — sharing the same state machine:
//
//   idle    → user sees the value, hover hints it's editable
//   editing → user has clicked; input is shown + focused
//   saving  → async save in flight, spinner
//   saved   → brief checkmark (1.2s), then back to idle
//   error   → toast already shown by caller, revert to idle
//
// onSave is async and returns ok/error so the cell can show the right
// state. Caller is responsible for revalidatePath / router.refresh
// inside the action. The cell falls back to optimistic display
// (showing the new value) while the save is in flight, then snaps
// back to the server value when router.refresh re-renders.

"use client";

import {
  useEffect,
  useRef,
  useState,
  useTransition,
  type KeyboardEvent,
  type ReactNode,
} from "react";
import { Check, Pencil, Loader2 } from "lucide-react";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

export type InlineEditResult = { ok: true } | { ok: false; message?: string };

type CommonProps = {
  /** Read-mode rendering. */
  display: ReactNode;
  /** Optional class for the read-mode wrapper. */
  className?: string;
  /** Hide the hover pencil — useful in dense tables. */
  noPencil?: boolean;
  /** Disable editing entirely (read-only without permissions). */
  readOnly?: boolean;
  /** Aligns the input + buttons in dense table cells. */
  align?: "left" | "right";
};

function ReadShell({
  display,
  className,
  noPencil,
  onClick,
  align = "left",
}: {
  display: ReactNode;
  className?: string;
  noPencil?: boolean;
  onClick: () => void;
  align?: "left" | "right";
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "group inline-flex items-center gap-1.5 rounded px-2 py-1 text-left transition-colors hover:bg-muted",
        align === "right" && "justify-end text-right",
        className,
      )}
    >
      <span>{display}</span>
      {!noPencil ? (
        <Pencil
          className="size-3 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100"
          aria-hidden
        />
      ) : null}
    </button>
  );
}

function SavedFlash() {
  return (
    <span className="inline-flex items-center gap-1 rounded px-2 py-1 text-sm text-emerald-700 dark:text-emerald-400">
      <Check className="size-3.5" aria-hidden />
    </span>
  );
}

function SavingSpinner() {
  return (
    <span className="inline-flex items-center px-2 py-1">
      <Loader2 className="size-3.5 animate-spin text-muted-foreground" />
    </span>
  );
}

// ---------------------------------------------------------------
// Text variant
// ---------------------------------------------------------------

export function InlineEditText({
  value,
  display,
  placeholder,
  maxLength,
  align,
  className,
  noPencil,
  readOnly,
  onSave,
}: CommonProps & {
  value: string;
  placeholder?: string;
  maxLength?: number;
  onSave: (next: string) => Promise<InlineEditResult>;
}) {
  const [mode, setMode] = useState<"idle" | "editing" | "saved">("idle");
  const [draft, setDraft] = useState(value);
  const [pending, startTransition] = useTransition();
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (mode === "editing") {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
  }, [mode]);
  useEffect(() => {
    if (mode === "saved") {
      const t = setTimeout(() => setMode("idle"), 1200);
      return () => clearTimeout(t);
    }
  }, [mode]);
  // Resync the draft when the upstream value changes (e.g. router.refresh).
  useEffect(() => {
    if (mode === "idle") setDraft(value);
  }, [value, mode]);

  function commit() {
    if (draft === value) {
      setMode("idle");
      return;
    }
    startTransition(async () => {
      const result = await onSave(draft);
      if (result.ok) {
        setMode("saved");
      } else {
        setDraft(value);
        setMode("idle");
      }
    });
  }

  if (readOnly) {
    return <span className={cn("px-2 py-1", className)}>{display}</span>;
  }
  if (pending) return <SavingSpinner />;
  if (mode === "saved") return <SavedFlash />;
  if (mode !== "editing") {
    return (
      <ReadShell
        display={display}
        className={className}
        noPencil={noPencil}
        onClick={() => {
          setDraft(value);
          setMode("editing");
        }}
        align={align}
      />
    );
  }
  return (
    <Input
      ref={inputRef}
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={onEditorKeyDown(commit, () => {
        setDraft(value);
        setMode("idle");
      })}
      placeholder={placeholder}
      maxLength={maxLength}
      className={cn("h-8", align === "right" && "text-right", className)}
    />
  );
}

// ---------------------------------------------------------------
// Number variant
// ---------------------------------------------------------------

export function InlineEditNumber({
  value,
  display,
  placeholder,
  align = "right",
  className,
  noPencil,
  readOnly,
  onSave,
}: CommonProps & {
  /** null = unset. */
  value: number | null;
  placeholder?: string;
  onSave: (next: number | null) => Promise<InlineEditResult>;
}) {
  const [mode, setMode] = useState<"idle" | "editing" | "saved">("idle");
  const [draft, setDraft] = useState(value === null ? "" : String(value));
  const [pending, startTransition] = useTransition();
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (mode === "editing") {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
  }, [mode]);
  useEffect(() => {
    if (mode === "saved") {
      const t = setTimeout(() => setMode("idle"), 1200);
      return () => clearTimeout(t);
    }
  }, [mode]);
  useEffect(() => {
    if (mode === "idle") setDraft(value === null ? "" : String(value));
  }, [value, mode]);

  function commit() {
    const trimmed = draft.trim();
    const next = trimmed === "" ? null : Number(trimmed);
    if (next === value) {
      setMode("idle");
      return;
    }
    if (next !== null && (Number.isNaN(next) || next < 0)) {
      setDraft(value === null ? "" : String(value));
      setMode("idle");
      return;
    }
    startTransition(async () => {
      const result = await onSave(next);
      if (result.ok) {
        setMode("saved");
      } else {
        setDraft(value === null ? "" : String(value));
        setMode("idle");
      }
    });
  }

  if (readOnly) {
    return <span className={cn("px-2 py-1", className)}>{display}</span>;
  }
  if (pending) return <SavingSpinner />;
  if (mode === "saved") return <SavedFlash />;
  if (mode !== "editing") {
    return (
      <ReadShell
        display={display}
        className={className}
        noPencil={noPencil}
        onClick={() => {
          setDraft(value === null ? "" : String(value));
          setMode("editing");
        }}
        align={align}
      />
    );
  }
  return (
    <Input
      ref={inputRef}
      type="number"
      inputMode="decimal"
      step="any"
      min={0}
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={onEditorKeyDown(commit, () => {
        setDraft(value === null ? "" : String(value));
        setMode("idle");
      })}
      placeholder={placeholder}
      className={cn(
        "h-8 max-w-[8rem]",
        align === "right" && "text-right",
        align === "right" && "ml-auto",
        className,
      )}
    />
  );
}

// ---------------------------------------------------------------
// Select variant
// ---------------------------------------------------------------

export type InlineSelectOption = { value: string; label: string };

export function InlineEditSelect({
  value,
  display,
  options,
  className,
  noPencil,
  readOnly,
  onSave,
}: CommonProps & {
  /** Empty string = no selection / "—". */
  value: string;
  options: InlineSelectOption[];
  onSave: (next: string) => Promise<InlineEditResult>;
}) {
  const [mode, setMode] = useState<"idle" | "editing" | "saved">("idle");
  const [draft, setDraft] = useState(value);
  const [pending, startTransition] = useTransition();
  const selectRef = useRef<HTMLSelectElement>(null);

  useEffect(() => {
    if (mode === "editing") selectRef.current?.focus();
  }, [mode]);
  useEffect(() => {
    if (mode === "saved") {
      const t = setTimeout(() => setMode("idle"), 1200);
      return () => clearTimeout(t);
    }
  }, [mode]);
  useEffect(() => {
    if (mode === "idle") setDraft(value);
  }, [value, mode]);

  function commitWith(next: string) {
    if (next === value) {
      setMode("idle");
      return;
    }
    startTransition(async () => {
      const result = await onSave(next);
      if (result.ok) {
        setMode("saved");
      } else {
        setDraft(value);
        setMode("idle");
      }
    });
  }

  if (readOnly) {
    return <span className={cn("px-2 py-1", className)}>{display}</span>;
  }
  if (pending) return <SavingSpinner />;
  if (mode === "saved") return <SavedFlash />;
  if (mode !== "editing") {
    return (
      <ReadShell
        display={display}
        className={className}
        noPencil={noPencil}
        onClick={() => {
          setDraft(value);
          setMode("editing");
        }}
      />
    );
  }
  return (
    <select
      ref={selectRef}
      value={draft}
      onChange={(e) => {
        setDraft(e.target.value);
        commitWith(e.target.value);
      }}
      onBlur={() => setMode("idle")}
      onKeyDown={(e) => {
        if (e.key === "Escape") {
          setDraft(value);
          setMode("idle");
        }
      }}
      className={cn(
        "h-8 rounded-md border border-input bg-background px-2 text-sm",
        className,
      )}
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

// ---------------------------------------------------------------
// Toggle variant — for booleans
// ---------------------------------------------------------------

export function InlineEditToggle({
  value,
  labels,
  onSave,
  readOnly,
}: {
  value: boolean;
  /** [offLabel, onLabel] */
  labels: [string, string];
  onSave: (next: boolean) => Promise<InlineEditResult>;
  readOnly?: boolean;
}) {
  const [draft, setDraft] = useState(value);
  const [pending, startTransition] = useTransition();
  useEffect(() => setDraft(value), [value]);

  function toggle() {
    const next = !draft;
    setDraft(next);
    startTransition(async () => {
      const result = await onSave(next);
      if (!result.ok) setDraft(value);
    });
  }

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={readOnly || pending}
      className={cn(
        "inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-medium transition-colors",
        draft
          ? "bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"
          : "bg-muted text-muted-foreground",
        !readOnly && "hover:opacity-80",
      )}
      aria-pressed={draft}
    >
      <span
        className={cn(
          "size-2 rounded-full",
          draft ? "bg-emerald-500" : "bg-muted-foreground/50",
        )}
        aria-hidden
      />
      {labels[draft ? 1 : 0]}
    </button>
  );
}

// ---------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------

function onEditorKeyDown(commit: () => void, cancel: () => void) {
  return (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter") {
      e.preventDefault();
      commit();
    } else if (e.key === "Escape") {
      e.preventDefault();
      cancel();
    }
  };
}
