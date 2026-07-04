const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "occasion-rules-test",
    firestore: {
      rules: fs.readFileSync(
        path.join(__dirname, "..", "firestore.rules"),
        "utf8"
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seed(uid, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("users").doc(uid).set(data);
  });
}

test("un acheteur peut créer son propre compte avec le rôle buyer", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer
      .collection("users")
      .doc("buyer1")
      .set({
        id: "buyer1",
        role: "buyer",
        identityStatus: "unverified",
        sellerStatus: "unverified",
      })
  );
});

test("un acheteur ne peut pas s'attribuer le rôle seller après création (auto-élévation)", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer" });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").update({ role: "seller" })
  );
});

test("un acheteur ne peut pas s'auto-vérifier l'identité (identityStatus: 'verified')", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer", identityStatus: "unverified" });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("users")
      .doc("buyer1")
      .update({ identityStatus: "verified", sellerStatus: "verified" })
  );
});

test("un acheteur ne peut pas s'attribuer un abonnement vendeur actif", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer" });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").update({
      sellerSubscriptionActive: true,
      sellerSubscriptionExpiresAt: new Date(),
    })
  );
});

test("un client ne peut pas passer une commande à 'paid' directement", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("orders").doc("order1").set({
      buyerId: "buyer1",
      status: "pending_payment",
    })
  );
  await assertFails(
    buyer.collection("orders").doc("order1").update({ status: "paid" })
  );
});

test("un client ne peut pas passer un paymentIntent à 'paid' directement", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("paymentIntents").doc("pi1").set({
      userId: "buyer1",
      status: "pending",
    })
  );
  await assertFails(
    buyer.collection("paymentIntents").doc("pi1").update({ status: "paid" })
  );
});

test("un client ne peut pas créer/modifier un document subscriptions", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("subscriptions").doc("buyer1").set({
      userId: "buyer1",
      isActive: true,
    })
  );
});

test("un client ne peut pas créer/modifier un document admins", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("admins").doc("buyer1").set({ uid: "buyer1" })
  );
});
