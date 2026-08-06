/**
 * One-time (idempotent) provisioning of the chat_rooms collection. Run by a
 * developer with the Admin SDK — never by end users or the deployed app,
 * per the `allow write: if false` on chat_rooms/{roomId} in
 * firestore.rules.
 *
 * Usage (from functions/, authenticated via `gcloud auth application-default
 * login` or GOOGLE_APPLICATION_CREDENTIALS pointed at a service account key
 * for the target project):
 *
 *   npx ts-node src/scripts/seedChatRooms.ts
 *
 * Safe to re-run: existing rooms are left untouched (in particular,
 * member_count is never reset once a room exists).
 */
import { db } from "../lib/admin";
import { SkillLevel } from "../lib/skillLevel";

interface RoomSeed {
  id: string;
  name: string;
  skillLevel: SkillLevel;
}

const ROOMS: RoomSeed[] = [
  { id: "beginner", name: "Beginner Traders", skillLevel: "beginner" },
  { id: "intermediate", name: "Intermediate Traders", skillLevel: "intermediate" },
  { id: "advanced", name: "Advanced Traders", skillLevel: "advanced" },
];

async function seed(): Promise<void> {
  for (const room of ROOMS) {
    const ref = db.collection("chat_rooms").doc(room.id);
    const snap = await ref.get();
    if (snap.exists) {
      console.log(`skip: chat_rooms/${room.id} already exists`);
      continue;
    }
    await ref.set({
      name: room.name,
      skill_level: room.skillLevel,
      member_count: 0,
      created_at: new Date(),
    });
    console.log(`created: chat_rooms/${room.id}`);
  }
}

seed()
  .then(() => {
    console.log("done");
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
