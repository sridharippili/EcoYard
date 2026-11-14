# HabitatEngine: the rules in prose

What the engine does, in English. Written so that the logic can be understood
(and re-implemented or reviewed) without reading Dart. The behaviour itself is
pinned by `fixtures/engine_cases.json`; this file explains why.

Code: `packages/ecoyard_core/lib/src/habitat_engine.dart`. Pure logic. No I/O,
no clock (the month is an input), no randomness: the same input always gives
the same answer.

## Input (`HabitatQuery`)

| Field | Meaning |
| --- | --- |
| `birdId` | The species (eBird code), or `null` when the species is unknown. `null` means "give advice that helps most birds". An id that is not in the content is a caller bug and throws `ArgumentError` |
| `space` | `yard`, `balcony` or `containers` |
| `sun` | `full`, `partial` or `shade` |
| `budget` | `free` (free actions only, **no plants**), `low` (free + low cost), `any` |
| `month` | 1-12. Anything else throws `ArgumentError` |
| `regionCode` | Must equal the content's region (`us-ne`). Anything else throws `UnsupportedRegionException`. The UI turns a state such as NJ into `us-ne` before calling |
| `journalBirdIds` | Birds the user already identified. Unknown ids (from older content) are **ignored**, never an error |

## Output (`HabitatRecommendation`)

- `actions`: at most **three**, in order.
- `freeFirstStep`: the first free action shown, or none.
- `plants`: every plant that fits, best first. The UI shows as many as fit.
- `plantsHiddenByFilters`: how many plants would help but were removed by sun, space or budget ("2 more need more sun").
- `supportNeeds`: each need of the bird with what could be done about it (below).
- `isGeneric`: true when `birdId` was null.
- `unmetNeeds`: needs with nothing available now.

## Which actions are possible

An action is **eligible** when all of these hold:

1. the query's month is in the action's `months` (season),
2. the query's space is in the action's `spaces`,
3. the budget allows its cost (`free` budget: free only),
4. it is not bird-specific, or the bird is in its `forBirdIds`. In generic mode
   (unknown bird) bird-specific actions are excluded.

Two more groups are tracked so the UI never says "nothing can be done" falsely:

- **later** actions pass 2-4 but fail 1: out of season now (`laterActionIds`).
- **more-budget** actions pass 1, 2 and 4 but fail 3: they cost more than the
  budget allows (`moreBudgetActionIds`). An action that fails the space test
  (a yard-only action on a balcony) is not reported anywhere.

## Which three are shown (the selection rule)

Fixed order (used for ties): free before low cost, then higher `priority`
(3 = most important), then a narrower season window (the chance passes
sooner), then id.

Pick up to three, one at a time:

- **Slot 1 is the best free action whenever one exists.** This is the
  guaranteed "free first step" from the mockup.
- Every slot picks the action with the highest score: the number of the bird's
  needs **not yet covered** by the actions already picked, plus **2** if the
  action is *featured* for this bird (`featuredForBirdIds`: a signature action,
  such as seed heads for the goldfinch or a nest box for the chickadee). Ties
  go to the fixed order.
- **No padding.** After slot 1, an action is shown only if it covers a need not
  yet covered. So fewer than three actions may be shown (a hummingbird on a
  balcony in July gets one). "Add a water source" followed by "Scrub the
  birdbath" is the same need twice, so only the first appears.
- Unknown bird: every kind of need counts (food, shelter, water, nesting, safety).

Why not simply "free always first"? Because free would then win every slot
whenever three free actions are eligible, and the one action that fixes a bird's
nesting need (a nest box, which costs a little) would never be shown, even
though the need list says it has a remedy. Free is guaranteed one slot and wins
ties; it does not win everything.

## Which plants, and in what order

A plant is shown when its `sun` includes the query's sun, its `spaces`
include the query's space, and the budget is not `free`. Plants are **not**
filtered by month: they have no planting season. The UI must not imply
"plant now" from this list; planting timing comes from the
`plant-native-shrub` action.

- Known bird: score = `10 x link weight` + the number of journal birds the
  plant also helps. Weight (1-3) dominates; the journal breaks ties. The bird
  being asked about does not count as its own journal entry.
- Unknown bird: score = the plant's total weight over all birds ("breadth") +
  the journal term.
- Ties: plant id.

## Need coverage (`supportNeeds`)

For each need of the bird:

- `remedyActionIds`: every eligible action (not only the three shown) that
  addresses it.
- `shownActionIds`: the part of that list among the three shown.
  `coveredByShownActions` is true when it is not empty.
- `laterActionIds`: actions that would address it but are out of season.
- `moreBudgetActionIds`: in-season actions that would address it but cost more
  than the budget allows ("a small budget would unlock this").
- `remedyPlantIds`: shown plants that address it for this bird.
- `hasRemedy`: false when nothing available **now, within this budget, space and
  season** helps. The UI must then say so, and point at `laterActionIds` or
  `moreBudgetActionIds` when either is not empty. It must never claim nothing
  can be done when one of them has an entry.

A need that has a remedy but is not among the three shown is "also possible".

## Known limits (deliberate, for now)

- **Needs are coarse.** Nearly every bird has the same five needs (food,
  shelter, nesting, water, safety). The engine cannot tell apart which action
  matters most for a species except through `featuredForBirdIds`, so every
  signature action has to be marked by hand in `content/actions.json`. Three are
  marked so far (seed heads, nest box, dead wood).
- A bird-specific action is **restricted** to its birds (`forBirdIds`); being
  *featured* only makes it win ties and slots for those birds.
- Plants have no planting season.
- Space is a hard filter with no "would work in a yard" hint.

## Changing the rules

The 21 cases in `fixtures/engine_cases.json` (once promoted: until then they are only a draft next to the tests, and nothing locks them) pin all of the above. Rules for
changing them:

1. Decide the new behaviour first, in this file.
2. Change the expected output in the fixture **by hand**, deliberately, and say
   why in the case's `why` and in the commit message (tagged `[fixtures]`).
3. Never edit a fixture to make a test pass.

Agents cannot edit `fixtures/` (a hook blocks it). Promoting the first draft:

```bash
mkdir -p fixtures && cp packages/ecoyard_core/test/engine_cases.draft.json fixtures/engine_cases.json
git rm packages/ecoyard_core/test/engine_cases.draft.json
git add fixtures && git commit -m "[fixtures] Promote engine cases (reviewed)"
```

After that the test loads `fixtures/engine_cases.json` instead of the draft, and
`scripts/release_check.sh` requires it to exist. Nothing else (pre-push, CI) fails
without it: those are guarded files the user must edit.
