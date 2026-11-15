# Privacy notice: BetterBetterUntis web version and sync (DRAFT)

> **DRAFT. Not legal advice.** This text is a starting point written for the
> maintainer. It must be reviewed (ideally by someone who knows the GDPR and
> the Austrian DSG / German BDSG) and every `[PLACEHOLDER]` filled in before
> it is published. Check it against what the Worker code (`worker/`) actually
> does at release time.

Last updated: [DATE]

**Scope:** this notice covers the BetterBetterUntis service at
`[HOSTNAME, e.g. bbu.example.org]`: the hosted web version, its WebUntis
relay and the optional sync. The service runs on Cloudflare Workers; there is
no self-hosted or home server. The phone apps (Android, iOS) talk to WebUntis
directly and only contact this service if you turn on sync.

## Who is responsible

[NAME], [POSTAL ADDRESS], e-mail [CONTACT E-MAIL] ("we"), runs this service
privately and free of charge. BetterBetterUntis is an unofficial open-source
app. It is not made by, endorsed by or affiliated with Untis GmbH or your
school.

## Summary

- The web version sends your WebUntis requests through our relay. They are
  **passed through, not stored**, and their contents are not logged.
- **Sync is optional and off by default.** Only if you turn it on do we store
  your own lesson notes and custom exams so they show up on your other
  devices. With **end-to-end encryption** turned on, we only store encrypted
  data we can't read.
- Turning sync off deletes everything we stored about you.
- No ads, no tracking, no analytics, no selling of data.

## 1. Web version and WebUntis relay

Browsers can't talk to WebUntis directly, so the web version (served from
`[HOSTNAME]`) sends its WebUntis requests to `[HOSTNAME]/proxy/...`, which
forwards them to your school's WebUntis server (only `*.webuntis.com`) and
returns the answer.

- **What passes through:** everything the app sends to and receives from
  WebUntis. This can include your login (user name, password or login token),
  your timetable, absences, exams, messages and other school data.
- **What is stored:** nothing. Requests and answers are only held in memory
  while they are forwarded. Your logins and timetable cache are stored in your
  browser (localStorage), not on the server. Cookies are not forwarded in
  either direction.
- **Logs:** the relay writes no logs of its own; request logging in
  Cloudflare Workers is turned off. Cloudflare processes your IP address and
  request metadata to deliver the service, for security (e.g. DDoS
  protection, rate limiting: requests are counted per IP address for about a
  minute) and in aggregate, non-content metrics (request counts, errors,
  [PLACEHOLDER: check dashboard analytics settings]).
- **Purpose:** to make the web version work at all.
- **Legal basis:** [PLACEHOLDER, e.g. GDPR Art. 6(1)(b) (providing the service
  you asked for) or Art. 6(1)(f) (legitimate interest in running and securing
  the service)].
- Your school's WebUntis server sees requests coming from Cloudflare's IP
  addresses instead of yours.

## 2. Sync (optional)

If you turn on sync in the app, we store:

| Data | Why |
|------|-----|
| WebUntis server (host), your school's login name and your numeric WebUntis user id | to know which notes belong to you; confirmed with WebUntis when a device signs in to sync |
| Your lesson notes and custom exams (text, the lesson they belong to, whether it is an exam), **or** with end-to-end encryption only encrypted blobs and pseudonymous keys | the content that is synced |
| With end-to-end encryption: the encryption header (salt, key-derivation settings, your data key encrypted with your passphrase and, if set up, your recovery code) | so your other devices can unlock the data with your passphrase |
| Hashes (SHA-256) of your sync session tokens, not the tokens themselves | to recognize your signed-in devices |
| Timestamps (when notes were changed, when the account and sessions were created and expire) and change counters | to merge changes from several devices |

Not stored: your WebUntis password (the sync never receives it), your name,
your timetable or any other school data.

When a device signs in to sync, the app sends a WebUntis login token once; the
server uses it for a single request to your school's WebUntis server to
confirm who you are and then discards it.

- **Purpose:** to sync your notes between your devices.
- **Legal basis:** your consent (GDPR Art. 6(1)(a)), given by turning sync on.
  [PLACEHOLDER: confirm.] You can withdraw it at any time by turning sync off;
  that doesn't affect what happened before.
- **Retention:** until you turn sync off or ask us to delete your data.
  Sessions expire after 90 days and are removed by a daily cleanup.
  [PLACEHOLDER: decide whether accounts without any session for N months are
  deleted automatically.]
- **Deletion:** turning sync off in the app deletes all your synced notes,
  your encryption header, your sessions and your account entry from the
  database immediately. Your devices keep their local copy.
- **Backups:** the database (Cloudflare D1) keeps an automatic point-in-time
  history ("Time Travel") so it can be restored after an error. Deleted data
  stays in that history for up to **[7 DAYS on the free plan / 30 DAYS on a
  paid plan: PLACEHOLDER, pick the one that applies]** and is then gone. We
  only use it to restore the whole database after a fault, not to look up
  individual users. If we ever have to restore, data you deleted in the
  meantime is deleted again [PLACEHOLDER: describe the procedure, see
  worker/README.md].

Please don't write sensitive personal data (e.g. health information, or
information about other people) into notes you sync without end-to-end
encryption.

## 3. End-to-end encryption (optional)

With end-to-end encryption on, your notes are encrypted on your device with a
key that is protected by your sync passphrase (and optionally a recovery
code) before they are uploaded. We, Cloudflare or anyone who gets a copy of
the database can't read the note texts, exam marks or which lessons they
belong to.

Limits:

- We still see which WebUntis account uses sync, how many notes you have,
  when they were changed, their approximate size (padded) and whether a note
  was deleted.
- In the **web version** the app, including the encryption code, is itself
  delivered by this service. Someone who controlled our Cloudflare account
  could deliver modified code. The phone apps don't have this weakness.
- If you forget your passphrase and have no recovery code, nobody can decrypt
  the synced copy. You can reset sync; your local notes stay on your devices
  and are uploaded again.

## 4. Hosting and processors

- **Cloudflare, Inc.** (101 Townsend St, San Francisco, CA 94107, USA) runs
  the service for us as our processor: Cloudflare Workers (web version,
  relay, sync), Cloudflare D1 (sync database) and its network (TLS, DDoS
  protection). All traffic to `[HOSTNAME]` passes through Cloudflare, which
  processes your IP address and request data under its Data Processing
  Addendum: https://www.cloudflare.com/cloudflare-customer-dpa/ . Cloudflare's
  privacy policy: https://www.cloudflare.com/privacypolicy/
- **Where data is processed:** Cloudflare handles requests in the data centre
  closest to you, which can be outside the EU. The D1 database is stored in
  [PLACEHOLDER: the location chosen when creating it, e.g. Western Europe
  (location hint "weur") / EU jurisdiction]. Transfers outside the EU/EEA are
  based on [PLACEHOLDER: e.g. the EU-US Data Privacy Framework, under which
  Cloudflare is certified, and the Standard Contractual Clauses in its DPA].
- **GitHub** (source code and app downloads) is not part of this service and
  has its own privacy policy.
- **Your school's WebUntis server** (Untis GmbH or your school) receives the
  requests you make, as it would with the official app.

## 5. Children and teenagers

Many users are students under 18. [PLACEHOLDER: In Austria, consent under
Art. 8 GDPR can be given from age 14 (§ 4(4) DSG); in Germany from 16. Users
below that age need a parent's or guardian's consent to turn sync on.] The
sync dialog in the app asks users to confirm this. We don't knowingly collect
more than described above, regardless of age.

## 6. Your rights

You have the right to access, rectify and erase your data, to restrict or
object to processing, to data portability, and to withdraw consent at any
time. The quickest way to erase your sync data is to turn sync off in the
app. For everything else, contact [CONTACT E-MAIL]. Because we store only
your school and a numeric WebUntis user id, we may ask for the sync identity
shown in the app's sync settings to find your data.

You can also complain to a data protection authority, e.g. the Austrian
Datenschutzbehörde (https://www.dsb.gv.at) [PLACEHOLDER: adapt to the
maintainer's jurisdiction].

## 7. Changes

We update this notice when the service changes. The current version is at
[URL]; its history is in the project's repository.

---

## Suggested in-app text for the sync opt-in dialog

> **Sync your notes?** Your custom exams and lesson details will be stored on
> the BetterBetterUntis sync server (run privately by the developer on
> Cloudflare), together with your school and WebUntis user id, so they show
> up on your other devices. Your password is never sent to sync; turn on
> end-to-end encryption so only your devices can read your notes, and turn
> sync off at any time to delete everything from the server.
> [If you are under 14 (Austria) / 16 (Germany), ask a parent first.]
> [Privacy notice] [Cancel] [Turn on sync]
