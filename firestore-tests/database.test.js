const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

// Règles Realtime Database (présence + "en train d'écrire") : chacun
// n'écrit que sa propre entrée, et uniquement au format de PresenceService.
let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "occasion-rtdb-rules-test",
    database: {
      rules: fs.readFileSync(
        path.join(__dirname, "..", "database.rules.json"),
        "utf8"
      ),
      host: "127.0.0.1",
      port: 9000,
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearDatabase();
});

test("présence : chacun écrit uniquement sa propre présence, au format { state: online|offline }", async () => {
  const alice = testEnv.authenticatedContext("alice").database();
  await assertSucceeds(alice.ref("presence/alice").set({ state: "online" }));
  await assertSucceeds(alice.ref("presence/alice").set({ state: "offline" }));
  await assertSucceeds(alice.ref("presence/alice").remove());
  await assertFails(alice.ref("presence/bob").set({ state: "online" }));
  await assertFails(alice.ref("presence/alice").set({ state: "invisible" }));
  await assertFails(
    alice.ref("presence/alice").set({ state: "online", payload: "x".repeat(1000) })
  );
  await assertFails(alice.ref("presence/alice").set("online"));
});

test("présence : lisible par tout utilisateur connecté, jamais anonymement", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.database().ref("presence/alice").set({ state: "online" });
  });
  await assertSucceeds(
    testEnv.authenticatedContext("bob").database().ref("presence/alice").get()
  );
  await assertFails(
    testEnv.unauthenticatedContext().database().ref("presence/alice").get()
  );
});

test("en train d'écrire : booléen uniquement, jamais pour quelqu'un d'autre", async () => {
  const alice = testEnv.authenticatedContext("alice").database();
  await assertSucceeds(alice.ref("typing/chat1/alice").set(true));
  await assertSucceeds(alice.ref("typing/chat1/alice").remove());
  await assertFails(alice.ref("typing/chat1/bob").set(true));
  await assertFails(alice.ref("typing/chat1/alice").set("x".repeat(5000)));
});
