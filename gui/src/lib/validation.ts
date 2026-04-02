// validation.ts — Field validation functions for parameter editing sidebar

export type ValidationResult =
  | { valid: true; value: number }
  | { valid: false; message: string };

export type StringValidationResult =
  | { valid: true; value: string }
  | { valid: false; message: string };

export function validateInt(value: string): ValidationResult {
  if (value.trim() === "") return { valid: false, message: "Required" };
  const n = Number(value);
  if (!Number.isInteger(n)) return { valid: false, message: "Must be a positive integer" };
  if (n <= 0) return { valid: false, message: "Must be a positive integer" };
  return { valid: true, value: n };
}

export function validateReal(value: string): ValidationResult {
  if (value.trim() === "") return { valid: false, message: "Required" };
  const n = Number(value);
  if (isNaN(n) || !isFinite(n)) return { valid: false, message: "Must be a finite number" };
  return { valid: true, value: n };
}

export function validatePositiveReal(value: string): ValidationResult {
  const result = validateReal(value);
  if (!result.valid) return result;
  if (result.value <= 0) return { valid: false, message: "Must be positive" };
  return result;
}

export function validateJuliaIdentifier(value: string): StringValidationResult {
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
