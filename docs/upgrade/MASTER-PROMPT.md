# MASTER DEVELOPMENT PROMPT
## Nearby Drop — Complete Application Upgrade, GTA VI–Inspired Themes, Advanced Features, Analytics & Release Preparation

### YOUR ROLE

You are my **Lead macOS Software Engineer, Senior SwiftUI/AppKit Developer, Product Designer, UX Specialist, File Transfer Protocol Engineer, Security Engineer, QA Engineer, and Product Growth Strategist**.

You are responsible for improving my existing macOS application, **Nearby Drop**, into a polished, reliable, distinctive and professional product.

I want you to perform actual development work, not simply provide recommendations.

**Your assignment is to inspect the existing project, understand its architecture, implement the requested improvements, verify their functionality, and deliver a working, tested application.**

Work independently wherever practical. Make reasonable engineering decisions, document your assumptions, and continue progressing through the implementation stages.

Do not repeatedly ask for confirmation about minor implementation choices.

However, obtain authorization before deploying to production, changing live server configuration, publishing releases, making purchases, or changing privacy-sensitive telemetry collection.

---

# 1. UNDERSTAND THE EXISTING APPLICATION

Nearby Drop is a native macOS menu bar application designed to transfer files between macOS and compatible Android/Windows Quick Share devices.

It also provides Android USB file management using MTP.

The application is written primarily in Swift and uses SwiftUI, AppKit, an existing NearbyShare framework, and an Objective-C USB bridge.

### Existing platform requirements

- macOS 14 or newer.
- Apple silicon and Intel support.
- Native macOS application.
- Existing proprietary distribution model.
- Existing Quick Share protocol compatibility.
- Existing Android USB/MTP capability.

### Existing application tabs

**SEND**
- Select files and folders.
- Drag and drop files.
- Discover nearby recipients.
- Transfer files wirelessly.
- Display transfer progress, speed, and estimated time remaining.
- Cancel and retry supported transfers.
- Generate Quick Share pairing QR codes.
- Support the existing Finder Share extension.

**RECEIVE**
- Advertise the Mac to nearby compatible devices.
- Accept or decline incoming transfers.
- Display receiving progress.
- Configure the download location.
- Scan supported Android-generated QR codes.
- Pause and resume receiving.

**TRANSFERS**
- Show locally persisted transfer history.
- Display sent and received files.
- Show available file and device information.

**USB**
- Detect compatible Android USB devices.
- Connect using MTP.
- Browse device storage.
- Navigate folders.
- Upload and download files.
- Download folders.
- Select save locations.
- Display operation progress.
- Cancel supported operations.

**SETTINGS**
- General preferences.
- Device name.
- Download location.
- Launch at login.
- Sound/haptic settings.
- Diagnostic reporting preferences.
- Local diagnostic export.
- Appearance controls.
- Software update functionality using Sparkle.

### Important existing limitations

- Wireless selection is currently capped at 128 files.
- USB does not automatically take over a failed wireless transfer.
- Device names are not secure device identities.
- Existing telemetry does not report transfer attempts or failures.
- Some compatibility scenarios have not been comprehensively verified.
- Signing and notarization need to be investigated against the actual repository and release environment.

**IMPORTANT: Inspect the actual source code before making changes.**

Do not assume that a feature described in this prompt is missing or implemented correctly until you verify the code.

Preserve the existing architecture where practical. Do not rewrite functioning protocol code merely to change the UI.

---

# 2. FIRST TASK — COMPLETE PROJECT AUDIT

Before implementation, inspect the complete codebase.

Important starting points:

- `README.md`
- `NearByDrop/AppDelegate.swift`
- `NearByDrop/TransferWindow.swift`
- `NearByDrop/USBView.swift`
- `NearByDrop/SettingsView.swift`
- `NearByDrop/ThemeManager.swift`
- `NearByDrop/OnboardingView.swift`
- `NearByDrop/UsageAnalytics.swift`
- `NearByDrop/AppSupport.swift`
- `NearByDrop/AppUpdater.swift`
- `NearbyShare/NearbyConnectionManager.swift`
- `NearbyShare/TransferFileSafety.swift`
- `ShareExtension/ShareViewController.swift`
- Existing diagnostics PHP/MySQL code.
- Existing tests and release scripts.

Locate additional relevant files as necessary.

Produce an internal audit identifying:

1. Existing implemented features.
2. Missing features.
3. Partially implemented features.
4. Known bugs and technical debt.
5. UI consistency problems.
6. Networking and discovery issues.
7. Transfer safety concerns.
8. USB performance and reliability issues.
9. Accessibility gaps.
10. Test coverage gaps.
11. Installation and distribution problems.
12. Areas where the proposed upgrades could cause regressions.

Create a working implementation checklist.

Use Git branches and logical commits. Preserve a recoverable baseline.

**Do not stop after this audit. Continue with actual implementation.**

---

# 3. COMPLETE GTA VI–INSPIRED VISUAL REDESIGN

This is one of my highest priorities.

I want a beautiful, professional visual identity inspired by the tropical, cinematic, neon-pink, neon-blue, palm-tree, sunset and Miami nightlife atmosphere associated with GTA VI.

I do not want a basic recoloring of the interface.

I want complete themes with their own coordinated backgrounds, components, gradients, illustrations, colors, interaction states and polished appearance.

The application must remain unmistakably a file-transfer utility.

### Important intellectual property requirement

Create original tropical artwork, illustrations, backgrounds and design elements.

Do not copy Rockstar Games logos, trademarked game artwork, characters, maps, music, sounds or proprietary assets.

Do not imply that Nearby Drop is officially affiliated with GTA VI or Rockstar Games.

## Theme A — VICE NIGHTS

This should be the signature theme.

### Visual direction

- Cinematic Miami nightlife.
- Deep purple and plum backgrounds.
- Vibrant neon pink.
- Ocean cyan.
- Warm sunset orange and gold.
- Subtle palm-tree silhouettes.
- Original retro-sunset artwork.
- Refined neon lighting.
- Dark glass-like surfaces.
- Beautiful gradients.
- Smooth, restrained animations.

### Suggested color palette

- Primary background: `#120D21`
- Secondary background: `#20162D`
- Neon pink: `#FF6CA8`
- Ocean cyan: `#6AE4EC`
- Sunset gold: `#FFC17D`
- Primary text: `#F9F6FE`
- Secondary text: `#CDBEDB`

These are starting design tokens, not an excuse to ignore contrast requirements.

### Main application design

Create a premium, consistent interface with:

- Custom background treatment.
- Clear navigation tabs.
- Attractive device cards.
- Purposeful glow effects.
- Modern icons.
- Carefully balanced spacing.
- Large readable transfer progress.
- Distinctive empty states.
- Consistent buttons.
- Refined microinteractions.
- Original palm/sunset artwork that never interferes with reading or controls.

The application should feel cinematic without sacrificing usability.

## Theme B — COASTAL SUNRISE

Create a lighter tropical variation.

Suggested palette:

- Cream: `#FFF0DF`
- Pastel pink: `#FFAFBC`
- Sunset orange: `#F8A56A`
- Tropical teal: `#368CA0`

Visual characteristics:

- Warm daytime aesthetic.
- Bright tropical atmosphere.
- Soft gradients.
- Pastel backgrounds.
- Elegant card designs.
- Highly readable interface.

## Theme C — MIDNIGHT ROUTE

Create a darker, more technical variation.

Suggested palette:

- Midnight navy: `#0B1724`
- Dark blue: `#162838`
- Electric cyan: `#70DADD`
- Warm amber: `#F5A66F`

Visual characteristics:

- Nighttime driving atmosphere.
- Minimal but premium interface.
- Technical status indicators.
- Subtle illuminated borders.
- Excellent readability.
- Less decorative artwork than Vice Nights.

## Theme architecture

Implement all three themes properly through the existing `ThemeManager` where appropriate.

The architecture must support:

- Centralized design tokens.
- Consistent colors.
- Backgrounds.
- Surfaces.
- Text hierarchy.
- Borders.
- Button styles.
- Focus indicators.
- Progress bars.
- Icons.
- Illustrations.
- Animations.
- Error and success states.

**Retain the existing System, Light and Dark appearance options.**

Users must be able to change themes immediately from Settings without restarting the application.

Persist their selection.

Provide visual previews of each theme.

## Apply themes everywhere

Do not stop at the main screen.

The selected theme must be consistently implemented in:

1. Main menu bar popover.
2. Send tab.
3. Receive tab.
4. Transfers tab.
5. USB tab.
6. General Settings.
7. Appearance Settings.
8. Transfer approval dialogs.
9. File-selection and device-selection interfaces where customization is supported.
10. Transfer progress.
11. Success states.
12. Error states.
13. Empty states.
14. Onboarding.
15. Troubleshooting interface.
16. Appropriate application-owned auxiliary windows.

Preserve native system dialogs where macOS controls their appearance.

## Animation requirements

Implement tasteful effects such as:

- Subtle button hover states.
- Soft highlight transitions.
- Progress animations.
- Receiving-state indicators.
- Smooth navigation transitions.
- Light accent glows during active operations.

Do not create distracting continuous effects.

Respect macOS Reduce Motion.

Respect Increase Contrast.

Support keyboard navigation and visible keyboard focus.

Ensure all important status information is communicated through text or icons, not color alone.

Check typography, contrast, layout clipping and smaller screen sizes.

**Success condition:** All themes should look like complete, intentionally designed products rather than basic color presets.

---

# 4. FEATURE UPGRADE — CONNECTION DOCTOR

Implement an integrated troubleshooting assistant called:

**Connection Doctor**

### Objective

Help users understand why a nearby device cannot be discovered, paired or connected.

### Required functionality

When a user cannot find their device, offer a prominent **Fix Connection** action.

Investigate the relevant conditions that can safely be checked, such as:

- Local network connectivity.
- Relevant application permissions.
- Wi-Fi availability.
- Receiving state.
- App/device discovery state.
- Supported network prerequisites.
- Known pairing errors.
- Unsupported protocol/client situations where identifiable.

Distinguish observed failures from suspected causes.

Never claim to detect remote-device settings that the Mac cannot actually inspect.

### User interface

Show understandable messages such as:

"Nearby device not detected."

"Check that Quick Share is enabled on the receiving device."

"Check local network connectivity."

"Try the QR connection workflow."

"Connect the device using USB instead."

Provide direct actions where possible.

### Additional requirements

- Show useful technical details behind an optional expandable section.
- Do not expose credentials or identifying diagnostic information.
- Categorize common errors.
- Provide clear recovery suggestions.
- Integrate existing QR and USB workflows rather than duplicating them.
- Offer retry only when appropriate.

---

# 5. FAVORITE DEVICES

Implement a favorite-recipient feature.

Users should be able to:

- Mark recipients as favorites.
- Quickly find favorite recipients.
- View favorites prominently in the Send interface.
- Remove favorites.
- See when a favorite is currently discoverable.

Favorites should reduce selection friction.

### Security restriction

A favorite device must not automatically become a trusted device.

Device names alone do not establish secure identity.

Do not bypass incoming transfer approval.

If persistent secure pairing is considered, design it separately using authenticated device identity.

For now, favorites are primarily a selection convenience.

---

# 6. SEND TEXT, LINKS AND CLIPBOARD CONTENT

Investigate and implement explicit user-triggered text and URL sharing with compatible devices.

### Required functionality

Provide a convenient way to:

- Type text.
- Paste text.
- Enter a URL.
- Select a recipient.
- Send the content through a compatible supported transfer path.

Validate actual Quick Share interoperability before declaring this feature supported.

If necessary, provide a clearly labeled fallback such as creating a temporary text file.

Do not silently monitor the clipboard.

Do not automatically collect copied passwords, messages or other clipboard information.

The user must initiate every sharing action.

Add appropriate success/error feedback.

---

# 7. SCREENSHOT-TO-DEVICE FEATURE

Implement a fast screenshot-sharing workflow.

### Desired experience

The user should be able to:

1. Trigger a screenshot action.
2. Select an appropriate macOS capture method.
3. Preview or confirm the result.
4. Choose a nearby device.
5. Send the screenshot.

Use supported macOS capture APIs and permissions.

Do not perform hidden screen recording or persistent screen capture.

If a shortcut is added, make it configurable and avoid conflicts with existing system shortcuts.

Integrate the existing transfer engine.

---

# 8. ADVANCED ANDROID USB FILE MANAGER

Improve the existing MTP interface without disrupting current functionality.

### Desired features

- More organized folder navigation.
- Better breadcrumbs.
- Optional dual-pane file management.
- Improved file selection.
- Multiple-file operations.
- Clear upload/download direction.
- Sorting by available metadata.
- Search within known folder listings, where technically feasible.
- Better progress feedback.
- Clear cancellation and error recovery.
- Better handling of slow Android devices.
- More understandable disconnected-device states.

A dual-pane interface may be better suited to a larger window instead of the compact menu bar popover.

Evaluate actual MTP performance and protocol limitations before implementing search or other advanced operations.

Never expose unsupported operations as if they work.

Preserve path validation and file-access safeguards.

---

# 9. LARGE-BATCH TRANSFER QUEUE

The current wireless selection has a 128-file limit.

Investigate how to provide a better experience for users transferring many files.

### Proposed behavior

Build a queue that can divide eligible large selections into supported transfer batches.

Potential features:

- Pending transfer batches.
- Current transfer.
- Completed transfers.
- Failed transfers.
- Individual retry where supported.
- Overall job progress.
- Clear cancellation handling.

Do not simply remove the current 128-file limit.

Respect protocol constraints and receiver behavior.

Validate source-file identities and access before starting queued work.

Do not promise byte-level resumption if the protocol cannot support it safely.

If this requires significant architectural changes, implement it behind an experimental feature flag and keep the existing stable workflow as the default until verified.

---

# 10. PROFESSIONAL ONBOARDING EXPERIENCE

Redesign the existing onboarding experience.

### Desired onboarding flow

**Step 1 — Welcome**

Explain Nearby Drop's core purpose in a concise, attractive interface.

**Step 2 — Send to Android**

Show how to start a wireless transfer.

**Step 3 — Receive on Mac**

Explain visibility and incoming approval.

**Step 4 — QR Connection**

Explain supported QR workflows and their network requirements.

**Step 5 — USB Mode**

Explain that the Android device must be unlocked and set to File transfer mode.

**Step 6 — Appearance**

Let the user preview and select an appearance, including Vice Nights.

**Step 7 — Privacy and Diagnostics**

Clearly disclose optional diagnostic reporting, explain the information collected and provide the existing available controls.

### Requirements

- Beautiful visual design.
- Clear instructions.
- Ability to revisit onboarding.
- Appropriate skip/back navigation.
- No misleading promises.
- Do not silently grant permissions or consent.
- Preserve existing settings and onboarding acknowledgment behavior.

---

# 11. ADVANCED ANALYTICS AND DIAGNOSTICS

The app already contains:

- `UsageAnalytics.swift`
- A first-party PHP/MySQL collector.
- A password-protected diagnostics dashboard.
- Locally exported diagnostic reports.

Current automatic events include:

- `first_launch`
- `app_opened`
- `transfer_completed`

These provide limited understanding of reliability.

I want a more useful analytics system.

## Add operational events

Implement a versioned schema for events such as:

- `transfer_started`
- `transfer_completed`
- `transfer_failed`
- `transfer_cancelled`
- `transfer_declined`
- `usb_operation_started`
- `usb_operation_finished`
- `troubleshooting_used`
- `onboarding_completed`

Add suitable stage-level timings and failure categories.

### Required technical attributes

Where appropriate, collect:

- Anonymous random installation ID already used by the app.
- App version.
- macOS version category.
- Coarse device category.
- Transfer direction.
- Transfer method.
- Bucketed file size.
- Bucketed file count.
- Transfer duration.
- Transfer outcome.
- Privacy-safe error category.
- Ephemeral transfer job ID.
- Transfer attempt ID.
- Event UUID.
- Schema version.

Do not add persistent hardware identifiers.

Avoid exact advertised device names and identifying metadata where unnecessary.

Never collect file contents, filenames, full local file paths, credentials, contacts or clipboard content.

## Accurate reliability measurements

Implement a clear transfer lifecycle.

A user-initiated transfer job may have several attempts.

Each attempt must have its own ID.

Retries must not inflate the number of unique transfer jobs.

Use event IDs to deduplicate telemetry delivery.

Distinguish:

- Successful jobs.
- Failed jobs.
- Cancelled jobs.
- Declined jobs.
- Pending jobs.
- Jobs with unknown outcomes.

A missing completion event does not automatically mean a transfer failed.

Include observation windows and explicit pending/unknown states.

Do not treat missing events from older app versions as evidence of failure.

## Data delivery and protection

Implement:

- Schema versioning.
- Compatibility with existing clients.
- Event validation.
- Idempotent ingestion.
- Retry with backoff.
- Queue delivery monitoring.
- Rate limiting.
- Server-side deduplication.
- Appropriate event sampling for low-value events.
- Explicit retention policies.

Preserve the existing user opt-out behavior.

Provide updated privacy disclosure before enabling expanded collection.

Do not expose the private backend credentials.

Do not deploy analytics database changes or enable expanded production collection without authorization.

Prepare and test migrations in a safe environment first.

---

# 12. ANALYTICS DASHBOARD UPGRADE

Improve the existing password-protected dashboard.

### Dashboard modules

**Overview**
- Reporting installation IDs.
- Active installation IDs.
- First launches.
- App opens.
- Successful wireless transfers.
- Successful USB operations where instrumented.
- Reporting coverage indicators.

**Transfer Reliability**
- Attempted jobs.
- Completed jobs.
- Failed jobs.
- Cancelled jobs.
- Pending/unknown outcomes.
- Success rate for cohorts with adequate telemetry.

**Performance**
- Transfer method.
- Size categories.
- Duration categories.
- Failure stages.
- Transfer performance by app version.

**User Activation**
- First launch.
- First attempted transfer.
- First successful transfer.
- Repeat usage.

**Troubleshooting**
- Most common error categories.
- Discovery-stage problems.
- Connection failures.
- Transfer-stage failures.
- Troubleshooting usage and subsequent outcomes.

**Collector Health**
- Accepted events.
- Rejected events.
- Duplicate events.
- Delayed delivery.
- Queue health.
- Server errors.
- Client version and schema coverage.

### Dashboard design

Use a clean, professional dashboard with:

- KPI cards.
- Useful charts.
- Date filtering.
- Method filtering.
- Version filtering.
- Clear definitions of metrics.
- Readable mobile/desktop layouts where practical.

Avoid fabricated data or misleading statistics.

Keep installation IDs, verified people, app downloads and active reporting installations conceptually separate.

Do not make false claims about unique users.

---

# 13. INSTALLATION, SIGNING AND RELEASE TRUST

Review how the application is built and distributed.

Investigate:

- Developer ID signing.
- Hardened Runtime.
- Entitlements.
- App sandbox requirements where applicable.
- Notarization.
- Ticket stapling.
- Clean installation.
- Gatekeeper behavior.
- Sparkle update signing.
- Installer/package format.
- Intel and Apple silicon compatibility.

Prepare a secure release workflow.

If signing credentials are available and authorized, use them through established secure mechanisms.

Do not print, commit or expose credentials.

If required Apple credentials are unavailable, prepare the release pipeline and document precisely which credential-dependent steps remain incomplete.

Do not falsely report that an app was notarized or publicly released.

Ensure updates do not interrupt active transfers.

---

# 14. WEBSITE, DOCUMENTATION AND GROWTH

Inspect the existing project website and documentation if they are available in the repository.

Prepare improvements that make Nearby Drop easier to understand and discover.

### Website recommendations

- Clear product description.
- Professional screenshots.
- Demonstration of wireless transfers.
- QR workflow explanation.
- USB file management explanation.
- Compatibility requirements.
- Installation instructions.
- Frequently asked questions.
- Troubleshooting guide.
- Privacy information.
- Download section.
- Appropriate release notes.

### Positioning

Communicate that Nearby Drop is a native Mac utility supporting compatible Quick Share transfers and Android USB file management.

Do not claim universal Quick Share compatibility or guaranteed transfer speeds.

Do not describe Nearby Drop as an official Google, Apple or Rockstar application.

### Growth preparation

Prepare:

- Better GitHub README.
- Screenshot set.
- Short demonstration storyboard.
- Release announcement draft.
- Comparison of capabilities against available alternatives.
- Mac/Android community launch plan.
- SEO-friendly help articles.
- Optional user feedback mechanism.

Do not publish or post externally without my authorization.

---

# 15. SECURITY AND PRIVACY — NON-NEGOTIABLE

Do not compromise security to make an interface appear faster.

Preserve:

- Recipient approval requirements.
- Encrypted wireless transfer behavior.
- Path validation.
- Safe file access.
- Transfer integrity checks.
- Source-file revalidation.
- Safe cancellation.
- Appropriate permission handling.
- Existing privacy controls.

Never interpret a matching advertised device name as proof of identity.

Never send file contents to analytics.

Never collect clipboard data in the background.

Never introduce hidden surveillance or background screen capture.

Avoid unnecessary personal information in error reports.

Any sensitive operation must be transparent and user-initiated.

---

# 16. TESTING AND QUALITY ASSURANCE

Implement automated tests wherever reasonable.

### Transfer testing

Test:

- Wireless sending.
- Wireless receiving.
- Incoming approval.
- Incoming decline.
- QR workflows in both directions.
- Retry behavior.
- Cancellation.
- Missing source files.
- Changed source files.
- File permission failures.
- Transfer integrity and file safety.
- Multiple-file operations.
- Device discovery and disconnect scenarios.
- Supported USB upload/download.
- USB interruption and recovery.

Do not claim a device scenario passed unless it was actually tested.

### UI testing

Verify:

- All three new themes.
- Existing System/Light/Dark options.
- Theme switching.
- Theme persistence.
- Every tab.
- Dialogs.
- Error screens.
- Empty states.
- Device cards.
- Progress indicators.
- Onboarding.
- Settings.
- Keyboard navigation.
- Text readability.
- Increased contrast.
- Reduced motion.

### Release validation

Verify supported builds for:

- Apple silicon Macs.
- Intel Macs.

Test actual hardware where available.

Where physical Android/Windows/Mac devices are unavailable, clearly separate automated validation from unperformed hardware verification.

Use mocks or fixtures for tests that cannot safely run against live devices.

Do not fabricate successful test results.

---

# 17. IMPLEMENTATION PHASES

Do the work in this order unless repository findings justify a safer dependency order.

## PHASE 1 — Audit and Baseline

- Inspect repository.
- Understand existing systems.
- Record current behavior.
- Run available tests.
- Identify risks.
- Create a prioritized implementation checklist.
- Establish a recoverable Git baseline.

## PHASE 2 — Visual Design System

- Upgrade ThemeManager.
- Create Vice Nights.
- Create Coastal Sunrise.
- Create Midnight Route.
- Retain existing themes.
- Design reusable UI components.
- Create original artwork and supporting assets.
- Implement theme previews.
- Apply themes across all screens.
- Perform accessibility testing.

## PHASE 3 — Reliability and Core UX

- Implement Connection Doctor.
- Add favorite recipients.
- Improve device picker.
- Improve transfer error messages.
- Improve onboarding.
- Validate QR and USB recovery guidance.

## PHASE 4 — Additional Transfer Features

- Explicit text and URL sharing.
- Screenshot-to-device workflow.
- USB browser improvements.
- Experimental large-batch transfer queue where technically safe.

## PHASE 5 — Analytics

- Implement event lifecycle.
- Add privacy-safe operational metrics.
- Prepare backend changes.
- Add dashboard views.
- Test event accounting.
- Verify opt-out behavior.
- Prepare updated privacy disclosure.

Do not activate new production telemetry without authorization.

## PHASE 6 — Release Engineering

- Review signing and notarization.
- Build secure packaging workflow.
- Verify Sparkle updates.
- Perform compatibility tests.
- Run regression testing.
- Document outstanding hardware tests.
- Prepare a release candidate.

## PHASE 7 — Marketing and Documentation

- Improve README and user guides.
- Prepare website improvements.
- Produce screenshots and release notes.
- Prepare growth experiments.
- Document download and activation measurements.

Do not publicly publish without authorization.

---

# 18. DEVELOPMENT RULES

Follow these rules throughout the project:

1. **Actually implement changes.** Do not substitute a written plan for code changes.

2. **Preserve existing working features.** Avoid unnecessary architectural rewrites.

3. **Keep changes modular.** Use reusable SwiftUI components and a centralized theme system.

4. **Maintain compatibility.** Support the existing macOS deployment target and architecture requirements.

5. **Prioritize reliability.** A beautiful UI is not acceptable if wireless or USB transfers become unstable.

6. **Do not fake functionality.** Every interactive control must perform its intended function.

7. **Handle errors properly.** Do not silently swallow failures.

8. **Respect protocol limitations.** Verify Quick Share/MTP behavior before promising capabilities.

9. **Avoid unapproved external actions.** Production deployment, analytics activation and public releases require authorization.

10. **Write meaningful tests.** Cover security-sensitive and failure-prone behavior.

11. **Keep documentation updated.** Code, UI and documentation must agree.

12. **Use version control.** Create understandable commits and keep changes reviewable.

13. **Continue autonomously.** Do not ask me to micromanage small implementation choices.

14. **Report blockers accurately.** If hardware, credentials, account access or deployment permissions are missing, continue with independent work and clearly document the blocked step.

15. **Never claim unverified completion.** Distinguish implemented, tested, partially implemented and blocked work.

---

# 19. RELEASE ACCEPTANCE CRITERIA

Do not call the project complete until the following have been verified or explicitly documented as blocked.

### Themes
- Three complete themes exist.
- Themes apply consistently to all application-owned screens.
- Existing appearance options remain functional.
- Theme switching persists.
- Accessibility requirements are met.
- Original artwork is used.

### Core application
- Sending still works.
- Receiving still works.
- Approval and security checks remain intact.
- QR workflows remain functional.
- USB transfers remain functional.
- Transfer history remains functional.
- Settings persist.
- Sparkle update behavior is preserved.

### New features
- Connection Doctor gives useful guidance.
- Favorites work without insecure approval bypass.
- Text/URL sharing is validated or clearly disabled if unsupported.
- Screenshot sharing works where permissions and supported transfer paths allow.
- USB improvements are functional.
- Large-batch queuing is implemented only if safe and adequately tested.

### Analytics
- Transfer jobs and attempts are correctly correlated.
- Retries are not double-counted.
- Pending and unknown outcomes are handled correctly.
- Opt-out remains functional.
- Privacy controls and disclosures are updated.
- No sensitive file contents are collected.
- Collector compatibility and delivery are tested.

### Release
- Available automated tests pass.
- Applicable builds succeed.
- Significant regressions are resolved.
- Signing/notarization status is accurately reported.
- Release notes and documentation are prepared.
- No unauthorized production deployment has occurred.

---

# 20. REPORTING FORMAT

After completing each major phase, provide:

**Phase Name**

**Implemented**
- Actual functionality implemented.
- Important files added or modified.

**Validation**
- Builds performed.
- Tests performed.
- Tests passed.
- Tests failed.
- Manual hardware verification.

**Outstanding Issues**
- Bugs.
- Limitations.
- External dependencies.
- Missing credentials or hardware.

**Next Phase**
- Work remaining.
- Dependencies.
- Implementation priority.

Do not produce generic status reports without corresponding code or verification evidence.

Maintain a master checklist showing the full project's progress.

---

# 21. FINAL DELIVERABLES

At the conclusion, I expect:

1. Updated Nearby Drop source code.
2. Fully integrated Vice Nights theme.
3. Fully integrated Coastal Sunrise theme.
4. Fully integrated Midnight Route theme.
5. Updated reusable UI components.
6. Connection Doctor.
7. Favorite-device functionality.
8. Explicit text/link sharing where supported.
9. Screenshot-sharing workflow.
10. Improved USB file manager.
11. Safe large-batch queue implementation or a documented, technically justified experimental status.
12. Updated onboarding.
13. Enhanced analytics instrumentation.
14. Updated analytics dashboard and safe migration scripts.
15. Updated privacy documentation.
16. Automated tests and test results.
17. Release preparation and signing/notarization documentation.
18. Updated README and user guides.
19. Website improvement assets and documentation where project access permits.
20. Final implementation and verification report.

Provide a working application build or release candidate when the available environment and signing requirements permit.

If something cannot be completed, explain precisely why, what was completed, and what is needed to finish it.

---

# 22. IMPORTANT FINAL INSTRUCTION

I do not want you to respond with only an analysis, recommendations, or a proposed roadmap.

**I want you to execute this development project.**

Start by inspecting the existing repository and running the baseline checks.

Then proceed through the implementation phases.

Make reasonable choices independently, prioritize core functionality and the complete visual theme system, and avoid introducing unnecessary complexity.

Do not sacrifice reliability, privacy, accessibility or performance for cosmetic effects.

The final Nearby Drop app should feel like a polished, professional macOS product with distinctive original Miami-sunset styling, intuitive Quick Share and USB workflows, useful diagnostics and a credible release process.

**Begin working on the actual project now.**