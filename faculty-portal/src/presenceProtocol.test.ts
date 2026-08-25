import { describe, expect, test } from "vitest";
import vector from "../../shared/fixtures/presence_v1_vector.json";
import {
  canonicalAttendanceProof,
  canonicalPresenceChallenge,
  canonicalPresenceResponse,
} from "./presenceProtocol";

describe("presence protocol", () => {
  test("TypeScript matches the shared presence vector", () => {
    expect(canonicalPresenceChallenge(vector.challenge)).toBe(vector.canonical_presence_challenge);
    expect(canonicalPresenceResponse(vector.response)).toBe(vector.canonical_presence_response);
    expect(canonicalAttendanceProof(vector.proof)).toBe(vector.canonical_attendance_proof);
  });
});
