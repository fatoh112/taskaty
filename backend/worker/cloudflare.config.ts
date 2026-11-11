import { bindings, defineConfig, triggers } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

const projectId = process.env.FIREBASE_PROJECT_ID;
const localDatabaseId = "00000000-0000-4000-8000-000000000003";

export default defineConfig(({ mode }) => ({
  worker: {
    name: "taskpulse-api",
    entrypoint,
    compatibilityDate: "2026-11-11",
    workersDev: true,
    env: {
      DB: bindings.d1({
        name: "taskpulse-db",
        ...((process.env.TASKPULSE_D1_ID || (mode === "development" ? localDatabaseId : undefined))
          ? { id: process.env.TASKPULSE_D1_ID || localDatabaseId }
          : {}),
      }),
      ...(projectId ? { FIREBASE_PROJECT_ID: bindings.text(projectId) } : {}),
    },
    triggers: [triggers.scheduled({ schedule: "* * * * *" })],
  },
}));
