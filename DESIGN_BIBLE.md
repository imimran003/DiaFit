# Diafit design bible

Status: baseline principles and measured current tokens. Values will be revised only with simulator evidence.

## Product character

Diafit should feel calm, editorial and food-led. It is a daily conversation with a trustworthy nutrition record—not a dashboard, social feed or medical device. Food supplies most of the colour. System state remains legible without relying on colour alone.

## Reference recording: principles retained

The 32.35-second reference uses a continuous light canvas, one dominant daily number, restrained secondary metrics, conversational chronology, isolated food objects and a composer that stays visually quiet. Its overview changes information density while preserving food identity and spatial continuity. These are principles, not assets or branding to copy.

Diafit-specific reinterpretation:

- Carbohydrates are the dominant daily metric; calories support them.
- Food images remain decorative and never imply exact verified portions.
- The overview spans multiple days and preserves day totals and meal identities.
- Motion communicates hierarchy and continuity; it does not decorate idle content.

## Baseline visual inventory

| Element | Current implementation | Audit direction |
| --- | --- | --- |
| Page background | Warm paper RGB ≈ `#F7F3EC` | Preserve a continuous adaptive canvas |
| Primary text | Near-black RGB ≈ `#1B1D1C` | Preserve; verify dark mode/increased contrast |
| Accent system | Lime, coral, lavender, saffron | Reduce to one semantic progress accent plus food colour |
| Typography | Rounded system body/title; serif 34 pt display | Reduce type-style mixing; support Dynamic Type |
| Cards | 28 pt translucent white, border, 22 pt shadow | Remove default card treatment; use spacing/rules first |
| Meal image | 238 pt full-width rounded rectangle | Make collapsed meals more scannable and image-led without consuming a full viewport |
| Composer | Ultra-thin glass capsule, shadow, suggestion pills | Simplify material and suggestion density; preserve 44 pt actions |
| Atlas | Blurred modal, 2-column 205 pt image tiles | Replace with multi-day spatial history and stable semantic zoom |
| Motion | Several unrelated springs and atlas blur/mask | Consolidate durations/springs and add Reduce Motion alternatives |

## Hierarchy

### Daily screen

1. Day identity and navigation.
2. Carbohydrates consumed/target as the dominant measure.
3. Calories and fibre as compact support where data exists.
4. Chronological thread.
5. Composer.

The daily header must remain recoverable with one obvious gesture or control. Opening a populated day must not strand the user at a context-free scroll tail.

### Collapsed meal

- Food visual.
- Meal name and serving.
- Time.
- Carbohydrates first; calories second.
- Estimated/confirmed state in text or symbol, not colour alone.

### Expanded meal

- Protein, fibre, fat and sugar.
- Components and editable portions.
- Assumptions, confidence and nutrition source.
- Original-photo versus generated/decorative image identity.
- Edit/delete/regenerate controls with explicit labels.

## Token policy

The baseline contains many ad hoc values. The redesign will consolidate around:

- Spacing: 4, 8, 12, 16, 24, 32, 48.
- Minimum touch target: 44×44 pt.
- Continuous corners: small 12, medium 18, large 28; avoid a new radius for every component.
- One low elevation for transient overlays only; permanent content should not float by default.
- Motion: quick feedback ≈0.16–0.20 s; state change ≈0.28–0.36 s; semantic zoom ≈0.45–0.55 s when Reduce Motion is off.
- Haptics: confirmation, destructive completion and camera capture only; never on scrolling or decorative transitions.

These are initial constraints, not a claim of completed implementation.

## Accessibility rules

- All fonts must scale; fixed sizes require a demonstrated optical reason and accessibility fallback.
- Secondary text must maintain contrast in light/dark and Increase Contrast.
- Gesture-only day paging, atlas dismissal and meal context actions require visible button alternatives.
- Reduce Motion replaces matched spatial travel with short cross-fades while preserving state.
- Reduce Transparency removes blur-dependent separation.
- Food images have concise meal labels; decorative layers are hidden from accessibility.
- Nutrient labels are spoken as full units, for example “49 grams carbohydrates,” not “49 g carbs.”

## Motion continuity checklist

For launch, meal insertion, expansion, day paging and semantic zoom inspect:

- stable image identity;
- no duplicate source/destination views;
- no corner-radius jump;
- no safe-area or background flash;
- text fades only after geometry is settled;
- correct z-order during reversal/cancellation;
- keyboard and composer move as one system;
- no off-screen task continues solely for animation.

