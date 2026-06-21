---
name: goal-refiner
description: "Use when the user gives a rough idea, broad objective, unfinished `/goal`, plan, issue, visual target, optimization target, or research task and wants it refined into a concise Codex Goal contract with one durable objective, clear boundaries, realistic environment, measurable progress, evidence-based completion, checkpoints, cleanup, blockers, and an output strictly under the hard cap of 4,000 characters."
---

# Goal Refiner

## Overview

Turn a rough intention into a scoped, auditable Codex Goal. A strong Goal is a thread-scoped completion contract: it says what must be true, how success will be checked, what constraints remain intact, how Codex should keep making progress, and when Codex should stop instead of claiming completion.

Use this for work that is bigger than one prompt, smaller than an open-ended backlog, and has a verifiable stopping condition. A Goal is best when the path is uncertain and Codex should follow a work -> check -> continue or complete loop without the user restating the objective after every turn.

The Goal prompt acts as the initial task and, more importantly, the exit criteria. Keep it compact and focused on the concrete outcome, measurable proof, and constraints that prevent false completion.

For large rewrites, migrations, or replacement plans, prefer `bounded-rewrite-goal`.

## Goal Fit

Good candidates:

- Performance optimization with a benchmark target.
- Flaky test investigation or bug hunts that require reproduction first.
- Dependency migrations, multi-step refactors, or plan implementations.
- Research or audit work that ends in an evidence-backed artifact.
- Prototypes or side projects with a clear build, launch, screenshot, behavior check, or feature checklist.

Poor candidates:

- One-off edits, explanations, copy rewrites, tiny obvious fixes, or small commands.
- Loose lists of unrelated backlog items.
- "Keep improving", "make it better", or "work on everything" without a finish line.
- Work where no evidence source can be named and the missing source cannot be safely assumed.
- Visual prompts whose only success condition is "100% pixel perfect" against an image, unless there is also a concrete spec, checklist, design-system standard, or visual comparison method.

## Workflow

1. Restate the user's rough idea in one sentence.
2. Decide whether a Goal is the right tool. If a normal prompt is clearly better, say that briefly and provide a one-turn prompt instead of forcing `/goal`.
3. Identify the smallest verifiable end state: one objective and one stopping condition. Avoid "keep improving", "make it better", or "work on everything".
4. Prefer measurable criteria: a number, threshold, parity target, coverage target, checklist, artifact standard, or explicitly bounded evidence grade.
5. Extract the operating contract: outcome, verification surface, progress measurement, realistic environment, constraints, boundaries, iteration policy, blocked stop condition, progress tracking, cleanup expectations, and final artifact.
6. Inspect live context when available and useful: repo status, relevant files, tests, commands, artifacts, docs, logs, URLs, prior thread evidence, source material, plan files, or known risky areas.
7. If the user asks to brainstorm first, refine in normal chat or plan mode first; if useful, have Codex create or reference a plan file before drafting the Goal.
8. If the user asks to be interviewed before the Goal is written, ask the smallest set of high-signal questions needed to define the contract, then wait.
9. If one missing fact would make the Goal risky or incoherent, ask one concise question. Otherwise make a conservative assumption and label it.
10.   Draft the Goal in the template below. The Goal should act as both the initial task request and the completion audit rubric.
11.   For long-running work, require compact checkpoint updates: current checkpoint, what was verified, what remains, and whether Codex is blocked.
12.   Include final cleanup when the task may involve failed experiments, generated helpers, speculative edits, or optimization attempts.
13.   Keep the final Goal text under 4,000 characters. Prefer concrete nouns, commands, files, metrics, and artifacts over explanation.
14.   Before returning the Goal, verify the total output is less than 4,000 characters, including `/goal`, assumptions, and all surrounding text. If it is 4,000 characters or more, shorten it until it is below the hard cap.
15.   Do not call goal tools or start a Goal unless the user explicitly asks to set/start/create it. Otherwise output a ready-to-use `/goal` draft.

## Goal Template

```text
/goal
Objective: <one concrete end state>
Scope: <files, commands, surfaces, systems, or research sources in bounds>
Non-goals: <what must not be changed or solved>
Verification: <tests, screenshots, benchmarks, diffs, logs, generated artifacts, citations, or manual checks that prove done>
Constraints: <behavior, API, UX, performance, budget, safety, compatibility, or operator limits that must hold>
Environment: <realistic local, preview, production-like, browser, device, simulator, dataset, account, or deployment surface needed for meaningful proof>
Iteration policy: <how Codex may choose next steps while preserving the objective; include checkpoint reporting for long runs>
Progress tracking: <meaningful commits, draft PR, status artifact, progress log, team update, or side-chat-friendly summary requirements>
Stop conditions: <exact blockers, missing access, failed prerequisites, or evidence that should end the run>
Final cleanup: <review, remove failed attempts, delete throwaway tools unless intentionally retained, document remaining uncertainty>
Completion rule: <when the Goal may be marked complete; must reference concrete evidence>
Final artifact: <PR, patch, report, audit, benchmark table, checklist, deployed URL, or other deliverable>
```

## Drafting Checklist

Each Goal should answer:

- What should be true when the work is done?
- Can the success condition use a concrete number, threshold, parity target, or explicit checklist?
- Which files, docs, issue, plan, logs, URLs, datasets, or source material should Codex inspect first?
- Which commands, artifacts, screenshots, benchmarks, citations, or manual checks prove progress?
- Does Codex need to create or use measurement tools such as benchmark scripts, visual diff tooling, eval suites, traces, or comparison reports?
- Is the environment realistic enough for the claim being made: same stack, flags, database shape, deployment path, browser session, simulator, physical device, or acceptable generated dataset?
- What must not regress or change while Codex works?
- What shortcuts would falsely satisfy the metric, such as reducing test coverage, changing the benchmark, inlining reference images, cropping screenshots, disabling build paths, or hiding failures?
- How should Codex choose the next best action after each attempt?
- How should progress be tracked during long runs: meaningful commits, draft PR, status artifact, progress log, Slack/team update, or scheduled check-in?
- What cleanup or review should happen after the target is reached?
- What blocker should stop the run, and what input would unlock progress?

## Visual Goals

Treat reference images and videos as context, not as the only definition of done. For visual work, prefer goals that combine reference media with feature checklists, design-system adherence, screenshots across named viewports, visual diff tooling, and explicit anti-shortcut constraints. If graphics, icons, or images are part of the reference, specify whether Codex should recreate them, use approved assets, generate placeholders, or defer exact asset matching.

## Quality Bar

- Narrow enough to audit, broad enough for Codex to choose useful next actions.
- Specific enough to verify, but open enough to support discovery.
- Completion is evidence-based, never "probably done"; Codex must compare the objective to concrete files, tests, logs, benchmark output, generated artifacts, screenshots, citations, or other inspectable evidence.
- The environment must match the claim. Do not let a preview, simulator, generated dataset, or disabled build path prove a production, physical-device, real-data, or full-deploy claim unless the Goal names that limitation.
- If a benchmark, test, browser check, or source access cannot run, the Goal should say that is a blocker.
- A budget limit or partial improvement is not completion.
- A gamed metric is not completion. The Goal must preserve the substance of the task, not just the measured number.
- Long-running Goals should leave useful progress evidence for later inspection.
- After the target is reached, Codex should review the work, clean up abandoned attempts, and report what was kept or removed before claiming completion when that risk applies.
- If exact proof may not be available, define how the final artifact must separate confirmed findings, approximate reconstructions, blocked claims, and remaining uncertainty.
- Keep lifecycle authority clear: the user or system controls pause, resume, clear, and budget-limited states; Codex may mark complete only when the evidence supports completion.

## Output Rules

- Start with the refined `/goal` when the task is Goal-fit, unless the user asked for critique first.
- If the user explicitly asked to be interviewed first, ask the questions instead of drafting.
- If the task is not Goal-fit, start with "This is better as a normal prompt:" and provide the concise prompt.
- Add at most one short "Assumptions" line if needed.
- Do not include long rationale, examples, or source quotes in the final goal.
- The complete returned text must be less than 4,000 characters. Count or otherwise verify the length when the draft is near the limit, and revise before returning if needed.
