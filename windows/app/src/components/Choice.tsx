import { useRef } from 'react';
import type { KeyboardEvent, ReactNode } from 'react';

export interface ChoiceOption<T extends string> {
  value: T;
  label: ReactNode;
  /** The text a screen reader says, when the label alone is not enough. */
  name?: string;
  disabled?: boolean;
}

/**
 * One group of choices (Frame Shape, Resolution, Codec): a radio group drawn as one track. It is
 * one tab stop; the arrow keys move to the next choice and choose it, as a radio group does, and
 * skip a choice that is disabled. Built from buttons, not native radio inputs (premium bar rule 72).
 */
export function Choice<T extends string>({
  label,
  value,
  options,
  onChange,
  disabled = false,
  group,
}: {
  label: string;
  value: T;
  options: ChoiceOption<T>[];
  onChange: (value: T) => void;
  disabled?: boolean;
  /** A stable name for the scripts: `data-group`. */
  group: string;
}) {
  const refs = useRef(new Map<T, HTMLButtonElement>());
  const enabled = options.filter((o) => !o.disabled);

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (disabled || event.ctrlKey || event.metaKey || event.altKey) return;
    const step = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? 1 : event.key === 'ArrowLeft' || event.key === 'ArrowUp' ? -1 : 0;
    if (!step) return;
    event.preventDefault();
    const at = enabled.findIndex((o) => o.value === value);
    const next = enabled[(at + step + enabled.length) % enabled.length];
    if (!next) return;
    onChange(next.value);
    refs.current.get(next.value)?.focus();
  }

  return (
    <div className="choice" role="radiogroup" aria-label={label} data-group={group} onKeyDown={onKeyDown}>
      {options.map((option) => {
        const checked = option.value === value;
        return (
          <button
            key={option.value}
            ref={(el) => {
              if (el) refs.current.set(option.value, el);
              else refs.current.delete(option.value);
            }}
            type="button"
            role="radio"
            className="choice-item"
            aria-checked={checked}
            aria-label={option.name}
            data-value={option.value}
            // One tab stop for the group: the checked choice, and the first one when none is.
            tabIndex={checked ? 0 : -1}
            disabled={disabled || option.disabled}
            onClick={() => onChange(option.value)}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}
