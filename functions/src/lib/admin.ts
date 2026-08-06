import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

// Every function file imports `db` from here rather than calling
// initializeApp() itself — Cloud Functions can load multiple function
// files into the same process, and initializeApp() throws if called twice.
if (getApps().length === 0) {
  initializeApp();
}

export const db = getFirestore();
