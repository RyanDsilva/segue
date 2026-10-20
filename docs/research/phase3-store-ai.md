# Phase 3 in the store: age rating, content rights, App Privacy, App Review and "Apple Intelligence"

Research ticket for P3-9 (phase 3 spec section 16.2, questions 19 and 20; R79). Read at source on 2026-10-20. Every quote below was read in the page's own HTML (downloaded with `curl` and searched as text), not through a summariser; a second-hand summary that could not be confirmed at source is marked as such and not relied on.

What Segue does, for the answers below: Apple's Foundation Models framework (on-device) and, optionally, one curated open-weights model (`mlx-community/Qwen3-4B-Instruct-2507-4bit`, Apache-2.0, 2,274,519,691 bytes in seven files, `curated-models.json`) that the user downloads by clicking Download in Settings > AI. It is fetched directly from `huggingface.co` (`/resolve/<pinned revision>/<file>`, which answers `302` to `us.aws.cdn.hf.co`), every file checked against a SHA-256 in the app, with a fixed `Segue/<version>` User-Agent and `Accept-Language: *` (`FileTransfer.swift`, R54, R66). Both models only restructure text the user pasted (section labels, title, artist) and turn a set request into filter chips. No chat, no generated prose shown as new content, nothing sent anywhere.

## 1. Age rating questionnaire

Sources: [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions) and [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating) (App Store Connect Help; no "last updated" shown).

**There is no AI, generative-AI, chatbot or assistant item in the questionnaire.** The full category list on the reference page is: In-App Controls (Parental Controls, Age Assurance); Capabilities (Unrestricted Web Access, User-Generated Content, Social Media, Social Media Disabled for Users Under 13, Messaging and Chat, Advertising); Mature Themes (Profanity or Crude Humor, Horror/Fear Themes, Alcohol, Tobacco, or Drug Use or References); Medical or Wellness (Medical or Treatment Information, Health or Wellness Topics); Sexuality or Nudity (Mature or Suggestive Themes, Sexual Content or Nudity, Graphic Sexual Content and Nudity); Violence (Cartoon or Fantasy Violence, Realistic Violence, Prolonged Graphic or Sadistic Realistic Violence, Guns or Other Weapons); Chance-Based Activities (Gambling, Simulated Gambling, Contests, Loot Boxes).

The items an AI feature could touch, verbatim:

- **User-Generated Content:** "Includes the broad distribution of content created by users as a component of the app's intended user experience. May include: broadly distributed videos, photos, text, and/or audio created by users of the app."
- **Messaging and Chat:** "Users can directly communicate with one another through features within the app. May include: text, voice and/or video chat, direct and/or group messaging, or public posting."
- **Unrestricted Web Access:** "Users can navigate to any webpage within the app or freely browse the web. May include: embedded browser functionality or browser app."

Segue: pasted text is never distributed to anyone (UGC is about *broad distribution*), there is no user-to-user communication, and the model download is a fixed URL, not browsing. The models only label what the user pasted, so they add no content a descriptor would cover. The answers in WS5 section 5 hold, now with the AI reasoning written in; expected result **4+** (the 4+ definition lists the capabilities that stay at 4+; none apply anyway).

A second-hand claim (a summariser and a 9to5Mac article) that Apple tells developers to "consider all app features, including AI chatbots" was **not found** on either Apple page above; it is not used here. It is still the sensible reading: answer for what the AI can surface, and Segue's can surface only the user's own text.

## 2. Content rights

Source: [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information): "**Content Rights** Apps that contain, show, or access third-party content must have all the necessary rights to that content or be otherwise permitted to use it under the laws of each App Store country or region in which they're available." The App Store Connect control itself (the two radio answers) is behind the login and could not be read; WS5 4.1 quotes the "No" answer as "No, it does not contain, show, or access third-party content".

Two things are new since WS5 chose "No":

- the app **accesses** third-party material: it downloads the Qwen3 model weights (Alibaba Cloud's Qwen team, Apache-2.0, converted by mlx-community). The Apache-2.0 licence grants the rights (use, reproduce, distribute), and Segue ships the licence text and credits (THIRD_PARTY_NOTICES.md, /acknowledgements);
- users paste chord sheets copied from websites. That is the user's own action on their own Mac, the same as typing; Segue does not fetch, host or show any site's content (URL import is phase 5, Personal-only, R61).

## 3. App Privacy label

Source: [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/):

- "'Collect' refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time."
- "'Third-party partners' refers to analytics tools, advertising networks, third-party SDKs, or other external vendors whose code you've added to your app."
- "if an authentication token or IP address is sent on a server call and not retained, or if data is sent to your servers then immediately discarded after servicing the request, you do not need to disclose this".

The download is Segue's own `URLSession` code (no Hugging Face SDK makes the request; `swift-huggingface` is linked for file types but does not perform the download), Segue receives nothing from it, and the request carries no user data beyond what every HTTP request carries (an IP address and Segue's fixed headers). Hugging Face is not a partner "whose code you've added" doing the collecting, and the developer neither receives nor can access the request. **The label does not change.** WS3 10.2 / WS5 section 6 stay as they are; the privacy policy (now live) already discloses the Hugging Face request and names Hugging Face as an independent provider (P3-9 commit a2efcea).

Guideline 5.1.2(i) (below) concerns sharing personal data *with* third-party AI; Segue shares nothing with any AI service, so no consent prompt is needed for the models.

## 4. App Review Guidelines

Source: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), "Last Updated: October 16, 2026".

- **2.5.2:** "Apps should be self-contained in their bundles, and may not read or write data outside the designated container area, nor may they download, install, or execute code which introduces or changes features or functionality of the app, including other apps." Model weights are data: the MLX runtime, the Metal kernels and every prompt are in the signed bundle, and the download adds no feature (the AI features exist and work with Apple Intelligence or with Segue's own rules without it). The app-group container is a designated container (R100). Custom models stay Personal-only (R62).
- **4.2.3:** "(i) Your app should work on its own without requiring installation of another app to function. (ii) If your app needs to download additional resources in order to function on initial launch, disclose the size of the download and prompt users before doing so." Segue needs nothing on launch; the optional model is downloaded only on click, with its size (2.27 GB), memory need and free disk shown first (Settings > AI).
- **5.1.2(i)** (current text): "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so." Not triggered (nothing is shared).
- **1.2 User-Generated Content** now names "AI content creation apps" among apps that "enable users to create, generate, upload, share, or otherwise contribute content" and need filtering, reporting and blocking. Segue does not generate content for others to see and has no sharing; not applicable. Worth one clause in the review notes ("only re-checks section labels, title and artist").
- **2.5.1:** "Apps should use APIs and frameworks for their intended purposes and indicate that integration in their app description." Supports naming Apple Intelligence in the description (section 5).
- **4.7** (mini apps, chatbots, plug-ins downloaded outside the binary): not applicable; a second-hand reading that 4.7 "permits model downloads" was not relied on.
- The **Notes** field: "The Notes field can contain up to 4000 bytes." Keywords: "One or more keywords (each greater than two characters) ... You can provide up to 100 bytes of content." Both from [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/). **So `ai` cannot be a keyword** (2 characters), which removes option (a) of question 18 as written.

What the notes must say (drafted in WS5 4.6): where the AI acts and what it does not do; that Apple Intelligence is used when enabled (Settings > AI shows status); the model's name, licence, size, that it downloads only on click from huggingface.co with the size shown first, that it is data checked against hashes and run by the bundled MLX framework, adds no code, and can be deleted; that everything works without either model; and NETWORK USE gains the download. Draft: 3,585 / 4,000 bytes.

No dedicated "uses AI" declaration exists among the App Store Connect product page properties documented in the help pages above (App information, Platform version information); nothing to fill in beyond the notes.

## 5. "Apple Intelligence" in marketing and in-app copy

Sources: [Apple Trademark List](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html) and [Guidelines for Using Apple Trademarks and Copyrights](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html); [App Store marketing guidelines](https://developer.apple.com/app-store/marketing/guidelines/); [HIG: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai).

- The trademark list has "**Apple Intelligence™** personal intelligence system" (a trademark, with "personal intelligence system" as its generic term).
- Compatibility use is allowed: developers "may use Apple ... or any other Apple word mark ... in a referential phrase on packaging or promotional/advertising materials to describe that the third party product is compatible with the referenced Apple product or technology", provided "a. The Apple word mark is not part of the product name. b. ... used in a referential phrase such as 'runs on,' 'for use with,' 'for,' or 'compatible with.' c. The Apple word mark appears less prominent than the product name. d. The product is in fact compatible with ... e. The reference to Apple does not create a sense of endorsement, sponsorship, or false association".
- Proper use: "Always spell and capitalize Apple's trademarks exactly as they are shown in the Apple Trademark List. Do not shorten or abbreviate Apple product names." Trademarks are adjectives, never plural or possessive, and "An appropriate generic term must appear after the trademark the first time it appears in a printed piece, and as often as is reasonable after that."
- Notices: for material distributed outside the United States, "Do not use trademark symbols" and use the international credit notice, e.g. "_________ is a trademark of Apple Inc." (the App Store listing and the website are worldwide, so no ™ symbol; a credit line instead).
- The App Store marketing guidelines and the HIG name no extra rule for Apple Intelligence. The HIG's Generative AI page asks apps to "Communicate where your app uses AI" (Segue's review sheet marks AI-decided fields with a sparkle, R117) and notes that the Foundation Models framework "requires a compatible device with Apple Intelligence turned on" (Segue's R69 note; its "Open System Settings" deep link `x-apple.systempreferences:com.apple.Siri-Settings.extension` was checked on this Mac on 2026-10-20 and opens "Apple Intelligence & Siri").

Where Segue stands: the app already says "Apple Intelligence" in Settings > AI (a section naming the system feature and its status) and in the low-memory note; the guide uses it through `AppleModelName`; the new privacy policy section says "Apple Intelligence (Apple's on-device model)"; the WS5 description draft says "It works with Apple Intelligence" (a referential phrase, less prominent than "Segue", exact spelling). Missing today: a credit notice line.

## 6. Questions for Ryan

Each is a decision only Ryan can make; the recommendation is the agent's reading of the evidence above. "Research ticket" is an option where the evidence is not conclusive.

**Q1. Age rating answers with AI (question 19, part 1).**
- (a) Answer every item No/None as in WS5 section 5, with the AI reasoning recorded (no AI item exists; UGC is about broad distribution; no chat; the download is not browsing). Expected 4+.
- (b) As (a), but override to 9+ to cover lyrics a user might paste.
- **Recommend a.** Apple rates the app's own content, and the models only restructure the user's text.

**Q2. Content rights (question 19, part 2).**
- (a) Keep "No, it does not contain, show, or access third-party content" (the weights are a data file the user chooses to fetch, not content Segue shows).
- (b) "Yes, it contains, shows, or accesses third-party content, and I have the necessary rights" (the app does fetch third-party material; Apache-2.0 grants the rights; notices ship in the app and on /acknowledgements).
- **Recommend b.** It is the literal reading of "access third-party content", the rights are in hand, and over-declaring costs nothing while under-declaring is a review risk.

**Q3. App Privacy label (question 19, part 3).**
- (a) No change: the developer receives nothing, the download is the app's own request, and an IP address on a request the developer does not retain needs no disclosure; the review notes and the privacy policy explain the download.
- (b) Add nothing to the label but answer the download in a review-notes sentence only (same as a; listed for completeness).
- (c) Research ticket: ask Apple (App Review contact form) before submission.
- **Recommend a.**

**Q4. "Apple Intelligence" wording (question 20).**
- (a) Use it referentially wherever it is true ("works with Apple Intelligence" in the description, "Apple Intelligence" in Settings > AI and the guide), never in a product or feature name, no ™ symbol, plus the credit line "Apple Intelligence is a trademark of Apple Inc." on the site's /acknowledgements page.
- (b) "On-device AI" only in marketing (description, site); "Apple Intelligence" only in-app where it names the system setting.
- (c) Avoid the term everywhere, including in-app (not recommended: users need the system name to find the setting, and the HIG uses it for exactly that).
- **Recommend a.** It meets every listed condition, and 2.5.1 asks apps to indicate framework integration in the description.

**Q5. Screenshots (question 17).**
- (a) Add a 9th: the paste review sheet (light), keeping the 5 dark / 3 light mix plus one light.
- (b) Replace shot 7 `minsize` with the paste review sheet.
- (c) Add two: the paste review sheet and the Arrange Sections sheet or the set assistant bar (10 is Apple's maximum for Mac).
- (d) No change.
- **Recommend a.** Paste is the headline phase 3 feature; the first three slots (search results) stay as they are.

**Q6. Keywords (question 18; R37 is 97 / 100 bytes).** `ai` is not allowed (2 characters).
- (a) Swap `cover` for `paste`: `chordpro,songbook,transpose,prompter,worship,hindi,guitar,piano,capo,nashville,stage,singer,paste` (97 bytes).
- (b) Swap `singer` for `metronome`: `chordpro,songbook,transpose,prompter,worship,hindi,guitar,piano,capo,nashville,stage,metronome,cover` (100 bytes). Metronome is a verified feature (visual on stage, a click in rehearsal); people searching for an audio metronome app may be disappointed.
- (c) Keep R37 unchanged (97 bytes).
- **Recommend c.** No AI-related term is both allowed and likely to be searched by this audience; the existing terms are all still true, and the description carries the AI story.

**Q7. Review notes byte budget.**
- (a) The WS5 4.6 rewrite: the AI paragraph, the paste try-it and the model download in NETWORK USE, paid for by tightening the Welcome, stage and Shortcuts paragraphs (3,585 / 4,000 bytes).
- (b) Keep the old notes word for word and add the AI paragraph by moving the Shortcuts (Apple events) paragraph into the review attachment video's narration (not possible: the attachment is silent, B-31).
- **Recommend a.**

**Q8. Screenshot song "Northbound Before Dawn" (R128 title search).** Apple Music has "Northbound Before Dawn (Delta Blues)" by Cora Flood, an exact title match. The other four approved titles had no hit on Apple Music (iTunes Search API), Spotify or Google; "Chai at Platform Four" drew one search-summary claim of a Bandcamp track that does not exist (the domain redirects to a sign-up page).
- (a) Drop it and run the set with four screenshot-only songs.
- (b) Replace it with a title that searched clean on Apple Music today: "Northbound at First Light" (keeps the slow closer, Bb, 76, 4:30), or one of the dropped titles that searched clean, "Second Set Shuffle" (A, 128, 3:05) or "Open Mic at the Laundromat" (E, 118, 2:55). ("Tin Roof Weather" has five Apple Music hits; "Copper Kettle Waltz" is close to Joan Baez's "Copper Kettle".)
- (c) Keep it (an obscure track; titles are not protected), against the search rule.
- **Recommend b, "Northbound at First Light"** (same role in the set; Spotify and Google still to be searched before use).

## 7. Title search log (R128)

Apple Music via the iTunes Search API (`entity=song`), Spotify via a `site:open.spotify.com` web search, Google via a web search for "<title> song", 2026-10-20.

| Title | Apple Music | Spotify | Google | Result |
|---|---|---|---|---|
| Lanterns on Pier Nine | no match ("Left of the Pier" by 9th Street Lanterns) | none | none | clean |
| Chai at Platform Four | 0 results | none | none (one unverifiable summary claim, see Q8) | clean |
| Northbound Before Dawn | **"Northbound Before Dawn (Delta Blues)", Cora Flood** | none | none | **hit** |
| Saltwater Telegraph | no match ("Dirtwater Telegraph" by Slang) | none | none | clean |
| Last Tram to Wexley | 0 results | none | none | clean |
