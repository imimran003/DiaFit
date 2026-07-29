# Profile experience

## Product intent

The Profile area gives Diafit enough user-owned context to personalize the diary
without turning the app into a clinical account dashboard. It is designed for
fitness-minded adults while remaining understandable to younger and older users.
Every field is optional until the user chooses to create a profile, and the
screen states clearly when information has not been provided.

## Navigation and hierarchy

The root experience uses five native tabs:

1. Today — the existing daily conversation and logging experience.
2. Diary — real logged meals grouped by day.
3. Insights — restrained summaries calculated from stored diary data.
4. Profile — identity, health context, food preferences, and goals.
5. Settings — units, haptics, reminders, permissions, privacy, and reset.

On iOS 26 and later, the native tab bar and selected custom surfaces use Liquid
Glass. Earlier supported systems use a semantic Material fallback. Content,
labels, and actions do not depend on transparency to remain understandable.

The Profile screen follows a simple vertical order:

- editorial title and short explanation;
- avatar, preferred name, and Edit action;
- personal details;
- health and food context;
- daily goals;
- local-storage privacy note.

## Stored profile data

`UserProfile` contains:

- preferred name;
- optional profile photo;
- date of birth, with age derived at display time;
- sex and optional user-entered gender identity;
- height and weight stored canonically in metric units;
- optional diabetes context;
- activity level;
- dietary pattern;
- allergies;
- calorie, carbohydrate, protein, and step goals;
- last-modified date.

`UserPreferences` contains:

- metric or imperial display units;
- preferred glucose unit;
- haptic preference.

The model deliberately excludes medication, insulin dosing, clinical diagnoses,
and emergency guidance.

## Persistence and privacy

Profile data uses the app's local file-persistence convention through a
repository protocol. The archive is versioned JSON written atomically under
Application Support and receives complete-until-first-authentication file
protection on device.

Corrupt or newer unsupported archives are left untouched. The UI reports a
recoverable storage problem instead of replacing the original file. Resetting a
profile clears only personal profile fields; meals, glucose readings, activity,
photos, and unit preferences remain intact.

No profile values are sent to a backend by this feature, and raw health-related
values must not be added to production analytics or crash logs.

## Empty states and microcopy

- Missing profile: “Set up your profile”
- Supporting copy: “Add a few details when you’re ready.”
- Missing value: “Not provided”
- No allergies: “None recorded”
- Privacy note: “Your profile stays on this device.”

No fabricated metrics, example identities, or completion pressure appear in the
normal runtime.

## Accessibility

- Every actionable control has at least a 44-point touch target.
- Rows expose combined VoiceOver labels such as “Height, 178 centimetres.”
- Metric values use stable text alignment and do not rely on colour.
- Native text styles and vertical scrolling support Dynamic Type.
- The experience uses native tab semantics, switches, pickers, and sheets.
- Liquid Glass is decorative; semantic Material remains available for older
  systems and Reduce Transparency compatibility.

## Verification

- Profile validation and persistence tests cover age boundaries, invalid values,
  round-trip storage, corrupt archives, and profile-only reset.
- UI automation covers navigation from Profile to Settings and verifies the
  clean first-run content.
- The experience was visually inspected on an iPhone 15 Pro simulator running
  iOS 26.5 in the empty-profile state, profile editor, and Settings screen.
