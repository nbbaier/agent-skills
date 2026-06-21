# Agent Skills

A collection of custom skills I've put together for coding agents.

## Skills

| Skill                                                      | Description                                                                                                        | Source                                                                                                                                   |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| [code-refactor-review](./skills/code-refactor-review/)     | Reviews code changes for reuse, composition, codebase consistency, and slop                                        | [Sahaj Jain](https://github.com/jnsahaj) ([gist](https://gist.github.com/jnsahaj/22806282b18a5c5136e0805d892dee39))                      |
| [goal-refiner](./skills/goal-refiner/)                     | Refines rough ideas into scoped Codex Goals with clear boundaries and measurable completion criteria               | [saburo](https://github.com/jskoiz) ([tweet](https://x.com/saboorow/status/2062658170515034157))                                         |
| [html-tools](./skills/html-tools/)                         | Build single-file HTML tools — self-contained HTML+JS+CSS applications that solve a specific problem               | [Simon Willison](https://github.com/simonw) ([post](https://simonwillison.net/2025/Dec/10/html-tools/))                                  |
| [ideation](./skills/ideation/)                             | Guides structured ideation through Socratic questioning to explore problems, opportunities, and solutions          | (self-created skill)                                                                                                                     |
| [implementation-guide](./skills/implementation-guide/)     | Generates comprehensive step-by-step implementation guides instead of writing code directly                        | [Geoffrey Litt](https://x.com/geoffreylitt/status/1990959999045005787) ([tweet](https://x.com/geoffreylitt/status/1990959999045005787))  |
| [logging-best-practices](./skills/logging-best-practices/) | Use before implementing logs in a medium to large scale production system                                          | [Joe Sadoski](https://github.com/jsadoski-rockhall) ([gist](https://gist.github.com/jsadoski-rockhall/4e3450c1c633902a49c0a7d8d857bd91)) |
| [react-effect-patterns](./skills/react-effect-patterns/)   | Guidelines for proper React useEffect usage and avoiding unnecessary Effects                                       | ([react docs](https://react.dev/learn/you-might-not-need-an-effect), probably)                                                           |
| [tufte-viz](./skills/tufte-viz/)                           | Ideate and critique data visualizations using Edward Tufte's principles for graphical integrity and data-ink ratio | [aparente](https://github.com/aparente) ([gist](https://gist.github.com/aparente/e48c353755958621b3c0004593105a90))                      |

---

## Installing Skills

Copy any skill directory to your agent's skills location or using Vercel's `skills` CLI:

```bash
npx skills add nbbaier/agent-skills
```
