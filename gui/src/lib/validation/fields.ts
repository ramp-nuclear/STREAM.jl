// fields.ts — Field validation helper functions (moved from gui/src/lib/validation.ts)
//
// D-16: Field-level validators (validateInt, validateReal, validatePositiveReal,
// validateJuliaIdentifier) are moved here from the top-level validation.ts so
// they live inside the new validation/ directory.
//
// IMPORTANT: The result type aliases are renamed here to avoid colliding with
// the D-11 ValidationResult type defined in ./types.ts:
//   - ValidationResult (old field-level) → FieldValidationResult
//   - StringValidationResult (old field-level) → FieldStringValidationResult
//
// Callers (NumericField.tsx, InstanceNameField.tsx, ParameterForm.tsx,
// codeGenerator.ts) are updated in Task 2 to import from this path and use
// the new type alias names.
//
// Logic, messages, and signatures are copied VERBATIM from validation.ts lines 1-43.
// Plan 13 deletes validation.ts after all topology consumers are rewired.

export type FieldValidationResult =
  | { valid: true; value: number }
  | { valid: false; message: string };

export type FieldStringValidationResult =
  | { valid: true; value: string }
  | { valid: false; message: string };

export function validateInt(value: string): FieldValidationResult {
  if (value.trim() === "") return { valid: false, message: "Required" };
  const n = Number(value);
  if (!Number.isInteger(n)) return { valid: false, message: "Must be a positive integer" };
  if (n <= 0) return { valid: false, message: "Must be a positive integer" };
  return { valid: true, value: n };
}

export function validateReal(value: string): FieldValidationResult {
  if (value.trim() === "") return { valid: false, message: "Required" };
  const n = Number(value);
  if (isNaN(n) || !isFinite(n)) return { valid: false, message: "Must be a finite number" };
  return { valid: true, value: n };
}

export function validatePositiveReal(value: string): FieldValidationResult {
  const result = validateReal(value);
  if (!result.valid) return result;
  if (result.value <= 0) return { valid: false, message: "Must be positive" };
  return result;
}

export function validateJuliaIdentifier(value: string): FieldStringValidationResult {
  if (value.trim() === "") return { valid: false, message: "Required" };
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(value)) {
    return {
      valid: false,
      message:
        "Must be a valid Julia identifier (letters, digits, underscores; start with letter or underscore)",
    };
  }
  return { valid: true, value };
}
