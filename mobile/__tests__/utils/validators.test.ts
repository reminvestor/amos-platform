import {
  isValidEmail,
  isStrongPassword,
  isValidUrl,
  isValidPhoneNumber,
  isValidSlug,
  isRequired,
  isValidLength,
  isValidCSV,
  validateForm,
  validationRules,
} from '@utils/validators';

describe('Validators', () => {
  describe('isValidEmail', () => {
    it('should accept valid emails', () => {
      expect(isValidEmail('test@example.com')).toBe(true);
      expect(isValidEmail('user.name@example.co.uk')).toBe(true);
      expect(isValidEmail('user+tag@example.com')).toBe(true);
    });

    it('should reject invalid emails', () => {
      expect(isValidEmail('invalid')).toBe(false);
      expect(isValidEmail('invalid@')).toBe(false);
      expect(isValidEmail('@example.com')).toBe(false);
      expect(isValidEmail('user@.com')).toBe(false);
    });
  });

  describe('isStrongPassword', () => {
    it('should accept strong passwords', () => {
      const result = isStrongPassword('StrongPass123!');
      expect(result.isValid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('should reject weak passwords', () => {
      const result = isStrongPassword('weak');
      expect(result.isValid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });

    it('should require at least 10 characters', () => {
      const result = isStrongPassword('Pass123!');
      expect(result.errors).toContain('Password must be at least 10 characters long');
    });

    it('should require uppercase letter', () => {
      const result = isStrongPassword('lowercase123!');
      expect(result.errors).toContain('Password must contain at least one uppercase letter');
    });

    it('should require lowercase letter', () => {
      const result = isStrongPassword('UPPERCASE123!');
      expect(result.errors).toContain('Password must contain at least one lowercase letter');
    });

    it('should require number', () => {
      const result = isStrongPassword('NoNumbers!');
      expect(result.errors).toContain('Password must contain at least one number');
    });

    it('should require special character', () => {
      const result = isStrongPassword('NoSpecial123');
      expect(result.errors).toContain('Password must contain at least one special character (!@#$%^&*)');
    });
  });

  describe('isValidUrl', () => {
    it('should accept valid URLs', () => {
      expect(isValidUrl('https://example.com')).toBe(true);
      expect(isValidUrl('http://example.com')).toBe(true);
      expect(isValidUrl('https://sub.example.com/path')).toBe(true);
    });

    it('should reject invalid URLs', () => {
      expect(isValidUrl('not a url')).toBe(false);
      expect(isValidUrl('example.com')).toBe(false);
    });
  });

  describe('isValidPhoneNumber', () => {
    it('should accept valid phone numbers', () => {
      expect(isValidPhoneNumber('555-123-4567')).toBe(true);
      expect(isValidPhoneNumber('5551234567')).toBe(true);
      expect(isValidPhoneNumber('+1-555-123-4567')).toBe(true);
    });

    it('should reject invalid phone numbers', () => {
      expect(isValidPhoneNumber('123')).toBe(false);
      expect(isValidPhoneNumber('abcdefghij')).toBe(false);
    });
  });

  describe('isValidSlug', () => {
    it('should accept valid slugs', () => {
      expect(isValidSlug('my-slug')).toBe(true);
      expect(isValidSlug('slug123')).toBe(true);
      expect(isValidSlug('my-slug-123')).toBe(true);
    });

    it('should reject invalid slugs', () => {
      expect(isValidSlug('My Slug')).toBe(false);
      expect(isValidSlug('my_slug')).toBe(false);
      expect(isValidSlug('MySlug')).toBe(false);
    });
  });

  describe('isRequired', () => {
    it('should accept non-empty strings', () => {
      expect(isRequired('text')).toBe(true);
    });

    it('should reject empty values', () => {
      expect(isRequired('')).toBe(false);
      expect(isRequired(null as any)).toBe(false);
      expect(isRequired(undefined)).toBe(false);
    });
  });

  describe('isValidLength', () => {
    it('should check minimum length', () => {
      const result = isValidLength('ab', 3);
      expect(result.isValid).toBe(false);
      expect(result.error).toContain('at least 3 characters');
    });

    it('should check maximum length', () => {
      const result = isValidLength('abcdef', undefined, 3);
      expect(result.isValid).toBe(false);
      expect(result.error).toContain('not exceed 3 characters');
    });

    it('should pass valid length', () => {
      expect(isValidLength('abc', 2, 5).isValid).toBe(true);
    });
  });

  describe('isValidCSV', () => {
    it('should accept valid CSV with email column', () => {
      const csv = 'email,name\ntest@example.com,Test User';
      const result = isValidCSV(csv);
      expect(result.isValid).toBe(true);
      expect(result.headers).toContain('email');
    });

    it('should reject CSV without email column', () => {
      const csv = 'name,phone\nTest,555-1234';
      const result = isValidCSV(csv);
      expect(result.isValid).toBe(false);
      expect(result.error).toContain('email');
    });

    it('should reject CSV with only header', () => {
      const result = isValidCSV('email');
      expect(result.isValid).toBe(false);
    });
  });

  describe('validateForm', () => {
    it('should validate multiple fields', () => {
      const data = { email: 'invalid', password: 'weak' };
      const rules = {
        email: validationRules.email,
        password: validationRules.minLength(10),
      };
      const result = validateForm(data, rules);
      expect(result.isValid).toBe(false);
      expect(result.errors.email).toBeDefined();
      expect(result.errors.password).toBeDefined();
    });

    it('should pass valid form', () => {
      const data = { email: 'test@example.com', password: 'StrongPass123!' };
      const rules = {
        email: validationRules.email,
        password: validationRules.minLength(10),
      };
      const result = validateForm(data, rules);
      expect(result.isValid).toBe(true);
      expect(Object.keys(result.errors)).toHaveLength(0);
    });
  });

  describe('validationRules', () => {
    it('email rule should validate email format', () => {
      const validResult = validationRules.email('test@example.com');
      expect(validResult.isValid).toBe(true);

      const invalidResult = validationRules.email('invalid');
      expect(invalidResult.isValid).toBe(false);
      expect(invalidResult.error).toBeDefined();
    });

    it('required rule should check for empty values', () => {
      const validResult = validationRules.required('text');
      expect(validResult.isValid).toBe(true);

      const invalidResult = validationRules.required('');
      expect(invalidResult.isValid).toBe(false);
    });

    it('minLength rule should validate minimum length', () => {
      const rule = validationRules.minLength(5);
      expect(rule('hello').isValid).toBe(true);
      expect(rule('hi').isValid).toBe(false);
    });

    it('maxLength rule should validate maximum length', () => {
      const rule = validationRules.maxLength(5);
      expect(rule('hello').isValid).toBe(true);
      expect(rule('toolong').isValid).toBe(false);
    });
  });
});
