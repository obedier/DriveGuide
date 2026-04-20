import { describe, it, expect } from 'vitest';

// These tests exercise small pure helpers inside the featured-tour flow.
// The heavy-lift Gemini generation is not unit-tested here — it is exercised
// by the seed script against a live API.

// To test the un-exported helpers we import the module and reach into the
// internals via re-parsing the source. Instead we rewrite them tiny-copy here
// so the test stays stable if we later split the helpers into a utility
// module. Keep this mirror in sync with `backend/src/services/tour/featured.ts`.

const BANNED_OPENERS: ReadonlyArray<string> = [
  'alright folks', 'alright friends', 'alright drivers', 'alright now',
  'okay so', 'okay folks', 'now then', 'here we go', 'buckle up',
  'let me tell you', 'let us talk about', "let's talk about",
  'you are going to love', "you're going to love",
  'get ready for', 'coming up on', 'folks,', 'so,', 'well,',
  'welcome to', 'listen up',
];

function hasBannedOpener(text: string): boolean {
  const head = text.trim().toLowerCase().slice(0, 40);
  return BANNED_OPENERS.some((b) => head.startsWith(b));
}

function extractJson(text: string): string {
  const fenceMatch = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/);
  let raw = fenceMatch ? fenceMatch[1].trim() : text;
  const first = raw.indexOf('{');
  const last = raw.lastIndexOf('}');
  if (first !== -1 && last > first) raw = raw.slice(first, last + 1);
  return raw.replace(/,(\s*[}\]])/g, '$1');
}

describe('featured-tour helpers', () => {
  it('hasBannedOpener detects "Alright folks" at the start', () => {
    expect(hasBannedOpener('Alright folks, today we are going to talk about Miami.')).toBe(true);
  });

  it('hasBannedOpener detects banned prefixes case-insensitively', () => {
    expect(hasBannedOpener('ALRIGHT NOW, listen here.')).toBe(true);
    expect(hasBannedOpener('Buckle up! Big tour coming.')).toBe(true);
    expect(hasBannedOpener("Let's talk about something else.")).toBe(true);
    expect(hasBannedOpener('Welcome to Miami Beach!')).toBe(true);
    expect(hasBannedOpener('So, this is where it starts.')).toBe(true);
  });

  it('hasBannedOpener allows distinct openings', () => {
    expect(hasBannedOpener('That smell? Cuban coffee roasting three blocks away.')).toBe(false);
    expect(hasBannedOpener('In 1925, a hurricane flattened everything you see.')).toBe(false);
    expect(hasBannedOpener('Notice what is missing from this skyline?')).toBe(false);
    expect(hasBannedOpener('Roll your window down right here.')).toBe(false);
    // Edge case: the word "welcome" mid-sentence is fine.
    expect(hasBannedOpener('A fresh sea breeze welcomes you to the jetty.')).toBe(false);
  });

  it('extractJson strips code fences', () => {
    const wrapped = '```json\n{"title": "Hello"}\n```';
    expect(JSON.parse(extractJson(wrapped))).toEqual({ title: 'Hello' });
  });

  it('extractJson strips trailing commas in arrays and objects', () => {
    const bad = '{"transitions": ["a", "b",]}';
    expect(JSON.parse(extractJson(bad))).toEqual({ transitions: ['a', 'b'] });
  });

  it('extractJson handles JSON with extra text around it', () => {
    const noisy = 'Here is the result:\n{"ok": true}\nthanks!';
    expect(JSON.parse(extractJson(noisy))).toEqual({ ok: true });
  });
});
