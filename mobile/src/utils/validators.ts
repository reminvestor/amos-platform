/**
 * Validate email format
 */
export function isValidEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Validate password strength
 */
export function isStrongPassword(password: string): {
  isValid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (password.length < 10) {
    errors.push('Password must be at least 10 characters long');
  }

  if (!/[A-Z]/.test(password)) {
    errors.push('Password must contain at least one uppercase letter');
  }

  if (!/[a-z]/.test(password)) {
    errors.push('Password must contain at least one lowercase letter');
  }

  if (!/[0-9]/.test(password)) {
    errors.push('Password must contain at least one number');
  }

  if (!/[!@#$%^&*]/.test(password)) {
    errors.push('Password must contain at least one special character (!@#$%^&*)');
  }

  return {
    isValid: errors.length === 0,
    errors,
  };
}

/**
 * Validate URL format
 */
export function isValidUrl(url: string): boolean {
  try {
    new URL(url);
    return true;
  } catch {
    return false;
  }
}

/**
 * Validate phone number (basic)
 */
export function isValidPhoneNumber(phone: string): boolean {
  // Removes common separators and checks length
  const digitsOnly = phone.replace(/\D/g, '');
  return digitsOnly.length >= 10 && digitsOnly.length <= 15;
}

/**
 * Validate slug format
 */
export function isValidSlug(slug: string): boolean {
  const slugRegex = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
  return slugRegex.test(slug);
}

/**
 * Validate required field
 */
export function isRequired(value: string | undefined | null): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

/**
 * Validate field length
 */
export function isValidLength(
  value: string,
  min?: number,
  max?: number
): { isValid: boolean; error?: string } {
  const length = value.length;

  if (min && length < min) {
    return {
      isValid: false,
      error: `Must be at least ${min} characters`,
    };
  }

  if (max && length > max) {
    return {
      isValid: false,
      error: `Must not exceed ${max} characters`,
    };
  }

  return { isValid: true };
}

/**
 * Validate CSV format
 */
export function isValidCSV(content: string): {
  isValid: boolean;
  headers?: string[];
  error?: string;
} {
  const lines = content.trim().split('\n');

  if (lines.length < 2) {
    return {
      isValid: false,
      error: 'CSV must contain at least a header and one data row',
    };
  }

  const headers = lines[0].split(',').map((h) => h.trim());

  // Check if email is in headers
  if (!headers.some((h) => h.toLowerCase() === 'email')) {
    return {
      isValid: false,
      error: 'CSV must contain an "email" column',
    };
  }

  return {
    isValid: true,
    headers,
  };
}

/**
 * Validate form data
 */
export function validateForm(
  data: Record<string, any>,
  rules: Record<string, (value: any) => { isValid: boolean; error?: string }>
): {
  isValid: boolean;
  errors: Record<string, string>;
} {
  const errors: Record<string, string> = {};

  for (const [field, rule] of Object.entries(rules)) {
    const result = rule(data[field]);
    if (!result.isValid && result.error) {
      errors[field] = result.error;
    }
  }

  return {
    isValid: Object.keys(errors).length === 0,
    errors,
  };
}

/**
 * Common validation rules
 */
export const validationRules = {
  email: (value: string) => ({
    isValid: isValidEmail(value),
    error: !isValidEmail(value) ? 'Invalid email format' : undefined,
  }),

  required: (value: any) => ({
    isValid: value !== null && value !== undefined && value !== '',
    error: value === null || value === undefined || value === '' ? 'This field is required' : undefined,
  }),

  minLength: (min: number) => (value: string) => {
    const isValid = isRequired(value) && value.length >= min;
    return {
      isValid,
      error: !isValid ? `Must be at least ${min} characters` : undefined,
    };
  },

  maxLength: (max: number) => (value: string) => {
    const isValid = !value || value.length <= max;
    return {
      isValid,
      error: !isValid ? `Must not exceed ${max} characters` : undefined,
    };
  },

  url: (value: string) => ({
    isValid: isValidUrl(value),
    error: !isValidUrl(value) ? 'Invalid URL format' : undefined,
  }),

  phone: (value: string) => ({
    isValid: isValidPhoneNumber(value),
    error: !isValidPhoneNumber(value) ? 'Invalid phone number' : undefined,
  }),
};
