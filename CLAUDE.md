# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Behavioral Guidelines

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

### Surgical Changes

**Touch only what you must. Clean up only your own mess.**

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

---

## Project Overview

Chinese-language Flutter app that answers "Do I need to pick up a package right now?" Users screenshot courier notifications (SMS or app), the app OCRs the image with Google ML Kit, parses out courier/tracking/pickup code/status, and manages pickup reminders. Android only (iOS planned).

## Build & Test

```bash
flutter run                       # Run on device/emulator
flutter build apk                 # Build Android APK
flutter test                      # Run all tests
flutter test test/some_test.dart  # Run single test
flutter analyze                   # Lint (flutter_lints + custom rules)
```

SDK constraint: `^3.6.0`. Linter adds: `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print`.

## Architecture: Four-Layer Unidirectional

```
ui/ ──────→ app/ ──────→ core/
  │                         ▲
  └────→ platform/ ────────┘
```

| Layer | Path | Role |
|-------|------|------|
| **core/** | `lib/core/` | Immutable pure Dart. Models, parser, engine, sanitizer. |
| **app/** | `lib/app/` | Orchestration. OCR pipeline, hero decision service. |
| **platform/** | `lib/platform/` | Thin adapters. ML Kit OCR, Hive storage, local notifications. |
| **ui/** | `lib/ui/` | Flutter rendering. Riverpod providers, screens, theme. |

### Hard Rule: `lib/core/` is frozen

`lib/core/` must NEVER import Flutter SDK, `platform/`, `app/`, or `ui/`. It contains only pure Dart logic. Before any core change, verify: no Flutter imports, no provider references, no Hive calls, no notification calls.

## State Management

Riverpod (`flutter_riverpod`). Root `ProviderScope` wraps the app in `main.dart`.

`PackageListNotifier` (StateNotifier) in `lib/ui/providers/package_provider.dart` is the single source of truth. All mutations go through this notifier; it auto-syncs to Hive via `_sync()`. Derived providers: `pendingPackagesProvider`, `completedPackagesProvider`, `groupedPendingPackagesProvider`, `heroDecisionProvider`.

## Text Parsing Pipeline

```
Raw text → TextSanitizer (noise filter) → TextPreprocessor (normalize) → TextParser.parseMulti() → ParseResult
```

Extractors in `lib/core/parser/extractors.dart`: `CourierExtractor`, `PickupCodeExtractor`, `TrackingNumberExtractor`, `PhoneTailExtractor`, `LocationExtractor`, `StatusExtractor`. Each returns `ExtractionResult<T>` with confidence score. `parseMulti()` splits multi-package text at pickup code boundaries.

Courier detection uses keyword matching + tracking number prefix patterns (e.g. `SF` → 顺丰, `JT` → 极兔).

## OCR Pipeline

`OcrPipeline.run()` in `lib/app/ocr_pipeline.dart`: OCR → sanitize → conflict detect → parse → confidence-based routing. High confidence (>=0.7) → Package; low confidence or high conflict → PendingConfirmation.

## Dual-Model Pattern

- `Package` (`lib/core/models/package.dart`) — immutable core model with `copyWith`, `transitionTo()`
- `HivePackage` (`lib/platform/storage/hive_package.dart`) — Hive serialization wrapper via `fromPackage()`/`toPackage()`

## Deduplication

`PackageListNotifier._findExistingPackage()` uses pickup code as the sole dedup key. Same pickup code = same package, regardless of tracking number, courier, or location. Status resolution enforces forward-only lifecycle: transit → delivering → arrived → pickedUp → archived.

## Persistence

Hive storage in `lib/platform/storage/`. Box named `"packages"` (constant `kPackagesBox` in `main.dart`). Four adapters: `PackageStatusAdapter` (typeId 0), `UrgencyLevelAdapter` (1), `CourierTypeAdapter` (2), `HivePackageAdapter` (3).

## Notifications

`NotificationAdapter` (`lib/platform/notification/notification_adapter.dart`): arrival notification (immediate on `arrived` status), 24-hour reminder via `zonedSchedule`. Notification IDs derived from package ID hash. Cancelled on `markPickedUp()`.

## Testing

Tests in `test/`. Fixtures in `test/fixtures/` organized as `good/`, `bad/`, `edge/`, `errors/`, `real_world/`. Parser regression tests use fixture files. Diagnostic tool: `bash diagnose_error.sh <ocr_raw_text_file>`.

## Common Workflows

**Add a courier**: enum case in `CourierType` (`lib/core/models/package.dart`) → detection logic in `CourierExtractor` → tests.

**Fix a parser bug**: add failing fixture to `test/fixtures/bad/` or `edge/` → fix extractor in `lib/core/parser/extractors.dart` → verify with `flutter test test/parser_regression_test.dart`.

**Add UI feature**: widget in `lib/ui/screens/home/widgets/` → provider in `lib/ui/providers/` if needed → use tokens from `lib/ui/constants/app_constants.dart`.

## Design Tokens

Colors, spacing, radii in `lib/ui/constants/app_constants.dart` (`AppColors`, `AppSpacing`, `AppRadius`). Theme in `lib/ui/theme/app_theme.dart` — Material 3.
