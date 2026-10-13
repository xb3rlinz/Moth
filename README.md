# Moth

A quiet, native iOS companion for keeping track of assignments.

Moth shows what needs attention now, keeps everything you have been assigned in order, and organizes it by semester and subject. Each assignment has notes, any number of photos, an optional due date, and a completion state. Everything is stored on your device: there are no accounts, no sync, and no network access.

Requires iOS 17 or later. Runs on iPhone (portrait) and iPad, in light and dark appearance.

## Using Moth

Moth has three tabs.

**Assignments** is the main workspace. One switch at the top changes how the same list is organized:

- **Upcoming**: everything still open, grouped by deadline (Overdue, Today, Tomorrow, Next 7 Days, Later, No Due Date). A one-line summary at the top says how much is overdue, due today, and open.
- **Recent**: every assignment, grouped by the day it was assigned.
- **Completed**: finished work, grouped by the day it was finished.

Tap the circle on a row to complete it. A just-completed row stays in place for a moment so a mis-tap is easy to undo. Tap anywhere else on the row to open the assignment. Rows also have swipe actions and a long-press menu for completing and deleting.

**Subjects** organizes work by semester and subject. Choose a semester from the heading, see its subjects with open and overdue counts, and open a subject to see its assignments (grouped by status or by the date assigned). The "+" inside a subject starts a new assignment already filed under that subject and semester. Semesters and subjects come from the assignments themselves; nothing extra is stored.

**Search** looks through titles, subjects, notes, and the date assigned (type `10/9/26`). Compact filter chips narrow the results by status (all, open, done), subject, the date assigned, and "due in 7 days" (open work, overdue included). Active filters are highlighted and **Clear** resets them all. The result count is always shown.

### Creating and editing

The "+" opens a new-assignment sheet with the cursor already in the title. Subjects and semesters you have used before appear as one-tap suggestions. Nothing is saved until you tap **Add**. **Cancel** asks first if you have entered anything, and the sheet cannot be swiped away by accident while it has content.

Opening an existing assignment edits it in place, and changes are saved as you make them. The due date is an explicit on/off switch, separate from the date itself. Photos are added with the system photo picker (several at once), shown as thumbnails, opened full screen with swipe, pinch and double-tap to zoom, and removed with confirmation. Deleting an assignment always asks first and also removes its photos.

## Design

Moth uses system typography, a warm neutral base, a single accent color (moonlight indigo), and red reserved for overdue work. Rows are plain and compact rather than cards, headings are quiet semibold titles, and translucency is limited to small floating controls such as the filter chips and the photo viewer buttons.

Every design decision lives in `Sources/Design/`:

| File | Contents |
| --- | --- |
| `Theme.swift` | Colors (light and dark), spacing, radii, sizes, type styles, motion, layout helpers |
| `Glass.swift` | The glass surface modifier, scrolling bar background, and button style |
| `Components.swift` | Section titles, empty states, filter chips, suggestion chips, meta text |

### Liquid Glass and SDK versions

Native Liquid Glass (`glassEffect`) is used when the app is **built with the iOS 26 SDK (Xcode 26, Swift 6.2) and run on iOS 26 or later**. In every other case (iOS 17 through 25, or a build made with an older Xcode) the same controls use a system material or a quiet neutral fill. The iOS 26 code is wrapped in `#if compiler(>=6.2)`, so the project still compiles with older Xcode versions, and the deployment target was not raised. Reduce Transparency always selects the fallback.

## Project layout

```
project.yml                       XcodeGen configuration
.github/workflows/build-ipa.yml   unsigned IPA build
Sources/
  MothApp.swift                   app entry point and SwiftData container
  ContentView.swift               the three tabs; refreshes "today" when the day, clock, time zone or locale changes
  AppState.swift                  shared state: current time, completion linger, delete confirmation
  Models.swift                    SwiftData models (Assignment, AssignmentPhoto)
  Helpers.swift                   dates, semesters, deadline buckets, grouping (no UI)
  AssignmentsView.swift           Upcoming / Recent / Completed
  SubjectsView.swift              semesters, subjects, subject detail
  SearchView.swift                search and filter chips
  AssignmentEditor.swift          new-assignment sheet and assignment detail
  SharedViews.swift               assignment row, completion button, new-assignment launcher
  Photos.swift                    photo import, thumbnails, section, full-screen viewer
  Design/                         the design system (see above)
```

## Data

Data is stored on the device with SwiftData. The stored model is the same as in earlier versions: `Assignment` (title, subject, semester, assigned date, optional due date, notes, completion flag and date, photos) and `AssignmentPhoto` (externally stored image data), so existing data opens as it was.

A semester is free text. `1/26` (first half of 2026) and `2/26` are shown as "Semester 1 · 2026" and sort chronologically; any other text is shown as typed.

Newly added photos are scaled down to at most 2400 pixels on the long edge and stored as JPEG. Photos added earlier are left exactly as they were. Image decoding happens off the main thread.

If the data store ever fails to open, Moth says so instead of crashing, and it never resets or deletes the store.

## Building

Moth uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

```sh
brew install xcodegen
xcodegen generate
open Moth.xcodeproj
```

Requirements:

- Xcode 15 or later. The iOS 17 SDK is the minimum because SwiftData, Observation and `ContentUnavailableView` need it.
- Swift language mode 5 (set in `project.yml`).
- A device or simulator running iOS 17 or later.
- Xcode 26 or later only if you want native Liquid Glass compiled in (see above).

The GitHub Actions workflow (`Build IPA`) generates the project and builds an unsigned IPA on a `macos-15` runner. The Xcode version that runner selects decides whether native Liquid Glass is compiled in. To use a specific newer Xcode, add a step that selects it (for example with the `maxim-lobanov/setup-xcode` action) before the build.

There is no asset catalog: the palette is defined in code, and the launch screen is the one generated by the `UILaunchScreen_Generation` setting in `project.yml`.

## Accessibility

Text uses system styles and scales with Dynamic Type (the Assignments switch becomes a menu at accessibility sizes). Controls have VoiceOver labels, each row reads as a single description with a custom "mark as completed" action, tap targets are at least 44 points, and Reduce Motion and Reduce Transparency are respected. Overdue work is never indicated by color alone: its text says "Overdue".
