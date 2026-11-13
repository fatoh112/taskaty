import { describe, expect, it } from "vitest";
import { ApiError, errorResponse, preflightResponse } from "../worker/src/http.ts";
import type { Env } from "../worker/src/types.ts";

const appOrigin = "http://127.0.0.1:5173";
const env = { APP_ORIGIN: appOrigin } as Env;

describe("browser CORS", () => {
  it("allows the configured origin and authenticated request headers", async () => {
    const response = preflightResponse(new Request("https://api.test/v1/teams", {
      method: "OPTIONS",
      headers: {
        Origin: appOrigin,
        "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "authorization,content-type",
      },
    }), env);

    expect(response.status).toBe(204);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe(appOrigin);
    expect(response.headers.get("Access-Control-Allow-Headers")).toContain("Authorization");
    expect(response.headers.get("Vary")).toBe("Origin");
  });

  it("rejects preflight from an unrelated origin", () => {
    const response = preflightResponse(new Request("https://api.test/v1/teams", {
      method: "OPTIONS",
      headers: { Origin: "https://untrusted.example", "Access-Control-Request-Method": "GET" },
    }), env);

    expect(response.status).toBe(403);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("keeps the allowed origin on authenticated API error responses", async () => {
    const response = errorResponse(new Request("https://api.test/v1/teams", {
      headers: { Origin: appOrigin, Authorization: "Bearer invalid" },
    }), env, new ApiError("INVALID_TOKEN", 401));

    expect(response.status).toBe(401);
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe(appOrigin);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "INVALID_TOKEN" } });
  });
});
