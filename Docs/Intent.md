# Diafit — design and engineering intent

## The point of view

Most nutrition trackers make someone translate their meal into a form. Diafit starts with what they would naturally say to a caring person: “I had my usual toast and eggs.” The agent makes the structure visible only after it has understood the thought.

The interface uses an ink-and-paper editorial palette instead of neon health-tech signals. The only saturated accent is reserved for the day’s carbohydrate total and moments that need attention; it should never read as an alarm.

## Information architecture

1. **Day thread** is the home. A horizontal swipe changes the day, preserving the feeling that each date has its own small story.
2. **Meal moments** are substantial, image-led objects inside that story. The data is one breath beneath the name, not a dense table.
3. **Meal atlas** is the zoomed-out memory of the day. It is a breathing, image-first grid—not a secondary dashboard. It uses the same meal identities as the thread, so the selected image visibly moves between places.
4. **The composer** accepts plain language. Suggestions make the first interaction feel easy, but never block typing.

## Motion language

- Presses use quick, small scale changes and a soft haptic, never a cartoon bounce.
- The atlas shares meal image geometry with the thread. This explains the navigation spatially instead of relying on a modal slide.
- A tiny Metal lens pass gently moves the food art while an image is “being made.” It is a material cue, not a visual effect for its own sake.
- Motion avoids flashing and runs only while the relevant surface is visible. Reduced Motion users get the same hierarchy with simple opacity transitions.

## Visual-material update

The food system is intentionally not a set of colored rectangles with stock images dropped inside. Each meal is a consistent studio cutout, keyed to alpha and placed on a restrained pigment field with a printed-fiber texture and a measured grounding shadow. This gives the same food object a believable physical identity in both the thread and the atlas.

The day thread no longer turns every thought into a floating white card. Meals are editorial moments, agent messages are carried by a fine lime rule, and the member’s own messages sit quietly on the paper. The atlas is a uniform two-column visual index: image first, metadata second, no alternating masonry gimmick.

## Integration shape

The in-app `ConversationCoordinator` is a local demo agent and `NutritionService` is intentionally protocol-based. Production should route the model, food database, and generated imagery through a server that can:

- call an authoritative nutrition database with serving-size provenance;
- retrieve only the member’s consented history;
- stream agent text and tool states;
- cache a food image using a normalized meal signature and art-direction prompt;
- return nutrition confidence so uncertainty is communicated in language, not implied precision.

For an editable conversational image workflow, OpenAI’s current docs recommend the Responses API; one-off generation can use the Image API. GPT Image 2 supports low quality for fast thumbnails and the documentation notes JPEG is faster than PNG when latency matters. See [the official image-generation guide](https://developers.openai.com/api/docs/guides/image-generation).

## Photo analysis extension

The photo flow is a conversation moment, not a scan-and-submit form. A camera button creates a temporary, metadata-stripped photo note. The next object in the thread is an explicit review: individual foods, a suggested serving, carbohydrates first, then only the two clarification questions that can meaningfully change an estimate. Confirmation is the moment that turns it into diary history; the original photo disappears by default, while the decorative editorial tile travels naturally into the atlas.

The visual system must never make recognition look more certain than it is. A generated image is marked decorative and cannot replace an original review photo. Food, oil/ghee, recipe, and serving assumptions remain available after logging; glycaemic data is not extrapolated. See [the detailed analysis architecture](PhotoAnalysisArchitecture.md).

## Safety boundary

Diafit is not a medical device and should never recommend insulin dosing, evaluate clinical risk, or present estimated food data as a lab result. Production needs explicit consent, secure storage, privacy review, accessibility QA, clinical copy review, and country-specific regulatory counsel.
