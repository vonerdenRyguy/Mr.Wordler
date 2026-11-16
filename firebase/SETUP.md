# Setting up Firebase for Family online (spec-08)

The Firebase project belongs to Ryan's Google account, so these steps are
done by Ryan in the Firebase console (https://console.firebase.google.com).
It takes about 10 minutes. Nothing here costs money: the free Spark plan is
plenty for a family game.

1. **Create a project.** Add project > name it `Mr Wordler`. When asked
   about Google Analytics, turn it **off** (we don't want to track kids).
2. **Add the Android app.** On the project page, tap the Android icon.
   - Package name: `com.example.namer_app`
   - Nickname: `Mr. Wordler`
   - Debug signing certificate SHA-1:
     `73:06:73:81:F6:DA:BB:06:7D:F6:F1:EF:23:EA:56:F2:BB:90:68:BE`
   - Register app, and skip the rest of that wizard (the file it offers
     is downloaded at the end instead, once Google sign-in is on).
3. **Add the SHA-256 as well.** Project settings (gear) > Your apps >
   Mr. Wordler > Add fingerprint:
   `FB:0A:87:5B:89:10:FF:7E:DF:B8:17:C9:A8:C4:90:E7:EF:99:63:14:0E:63:94:E1:E2:C2:36:ED:EA:88:49:18`
4. **Turn on sign-in.** Build > Authentication > Get started >
   Sign-in method, and enable:
   - **Google** (pick your email as the support email)
   - **Email/Password**, then inside it switch on **Email link
     (passwordless sign-in)**. Leave plain passwords off if it lets you.
   - **Anonymous** (used only for children under 13, who never give an
     email; a grown-up's yes is what lets them in)
5. **Turn on Hosting.** Build > Hosting > Get started, and click through.
   Then publish `firebase/hosting/` from a terminal, in the `firebase`
   folder: `npx firebase-tools login`, then
   `npx firebase-tools deploy --only hosting`. Its
   `.well-known/assetlinks.json` is what lets Android open emailed sign-in
   links in the app; without it they land on "Site Not Found". (Done
   2026-11-16. A release key's SHA-256 must be added to that file too.)
6. **Create the database.** Build > Firestore Database > Create database
   > a US location > **Start in production mode**.
7. **Paste the rules.** In Firestore > Rules, replace everything with the
   contents of `firebase/firestore.rules` and Publish.
8. **Download the app's settings file.** Project settings (gear) > Your
   apps > Mr. Wordler > **google-services.json**. Leave it in Downloads;
   Claude Code moves it into `android/app/`. (Download it after step 4:
   it carries the Google sign-in key.)

Then tell Claude Code it's done.

## Before the app is public (not needed for testing in our family)

- A privacy policy page, linked from the app and the store listing.
- A lawyer's look at the under-13 consent step (COPPA).
- A release signing key, whose SHA-1 and SHA-256 are added in step 3.
- A real package name instead of `com.example.namer_app` (this means
  adding a new Android app in Firebase).
