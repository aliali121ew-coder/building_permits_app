/**
 * Secure password hashing using Web Crypto PBKDF2 with SHA-256
 * Runs natively in Cloudflare Workers environment without external dependencies
 */

const ITERATIONS = 100000;

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex: string): Uint8Array {
  const pairs = hex.match(/.{1,2}/g) ?? [];
  return new Uint8Array(pairs.map(byte => parseInt(byte, 16)));
}

async function derive(password: string, salt: Uint8Array): Promise<Uint8Array> {
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    { name: 'PBKDF2' },
    false,
    ['deriveBits']
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: ITERATIONS, hash: 'SHA-256' },
    keyMaterial,
    256
  );
  return new Uint8Array(bits);
}

/** مقارنة ثابتة الزمن لمنع هجمات التوقيت */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await derive(password, salt);
  return `${toHex(salt)}:${toHex(hash)}`;
}

export async function verifyPassword(password: string, storedHash: string): Promise<boolean> {
  try {
    const parts = storedHash.split(':');
    if (parts.length !== 2) return false;
    const salt = fromHex(parts[0]);
    const expected = fromHex(parts[1]);
    const actual = await derive(password, salt);
    return timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}
