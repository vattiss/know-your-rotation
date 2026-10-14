# Contributing to Know Your Rotation

Thanks for helping! The addon is a rotation helper for **WoW Forever** (interface `16001`), made for leveling and learning a class. It shows the next spell; it never casts anything.

## The most useful help: reports from the game

Most spells above level 20 have not been played yet, so a good report is worth as much as code. Open an issue with the **Bug or wrong suggestion** form and paste the debug report ([how to collect it](README.md#collecting-data-for-a-bug-report)). Ideas and missing spells go in the **Idea or missing spell** form.

## Scope

- WoW Forever only. No other client or version.
- English only. Every player-facing string lives in `Locale.lua` (`ns.T("KEY")`).
- A helper, not a bot: nothing may cast, target or move for the player.
- Leveling and learning first: a sensible order, not a tuned raid rotation.
- No combat log reads (`CombatLogGetCurrentEventInfo` gets the addon blocked).

For a bigger change (a new cue, a new option, a different list order for a class), open an issue first so we can agree on it before you write the code.

## Making a pull request

1. Fork the repository, create a branch from `main`, and get the Blizzard UI source: `git submodule update --init --depth 1` (it lands in `ref/wow-ui-source`).
2. **Read before you change:** [AGENTS.md](AGENTS.md) says which file does what; the matching section of [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains it. Look up every Blizzard function or event you call in `ref/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated`: argument and return order, `Nilable`, and the `Secret*` flags (a secret value cannot be compared or added).
3. Keep the style: tabs, `local addonName, ns = ...` at the top of each file, short comments that say why.
4. **Tests:** every change to addon code comes with tests in `tests/*_spec.lua`. Line coverage is 100 % for every file and CI enforces it. Code no test can reach is dead code: remove it.
5. **Docs:** update the ARCHITECTURE section you touched, and `README.md` when players can notice the change.
6. Do not bump the version or edit `VERSION.txt` / the TOC version: releases are made by the maintainer.
7. Write the commit messages and the pull request title as [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `fix(rogue): finish with Eviscerate from 2 points on weak mobs`. The types and scopes are listed in [AGENTS.md](AGENTS.md#commit-messages).
8. Open the pull request against `main` and fill in the template.

### Checks to run before you push

| Check | Command |
| --- | --- |
| Tests and coverage | `luajit tests/run.lua --min=100` (`--uncovered` lists the missing lines) |
| Lint | `luacheck *.lua tests tools types` |
| Format | `stylua .` (CI runs `stylua --check .`) |
| Types | `lua-language-server --check=. --checklevel=Warning` (zero warnings) |

You need [LuaJIT](https://luajit.org/), [luacheck](https://github.com/lunarmodules/luacheck), [StyLua](https://github.com/JohnnyMorganz/StyLua) and [LuaLS](https://github.com/LuaLS/lua-language-server). Without a C compiler for LuaFileSystem, run luacheck with `LUA_PATH="<repo>/tools/?.lua;;"` (`tools/lfs.lua` stands in). Every push and pull request also runs these checks on GitHub.

A new Blizzard global goes into `.luacheckrc`. A new addon `.lua` file goes into the TOC, `tests/wow.lua` and `tests/run.lua` (`ADDON_FILES`), or CI and the coverage report miss it.

### Changing a spell list

Lists live in `Lists.lua`, spell data in `Data.lua`. Resolve spells by name through the spellbook (`ns.API.Resolve`), not by a fixed ID. In the pull request say which class, level and role you played it on, and why the new order is better while leveling. Do not raise `listVersion`: saved lists merge the new default steps on their own.

### Testing in game

The unit tests run against a stand-in of the WoW API (`tests/wow.lua`); the real client can still differ. If you can, copy the root `*.lua` files and the TOC into `World of Warcraft\_classic_beta_\Interface\AddOns\KnowYourRotation`, play with **Collect debug data** on, and say in the pull request what you saw. Never copy `ref/`, `tests/` or `tools/` into the AddOns folder.

## License

By contributing you agree that your contribution is released under the [MIT License](LICENSE) of this project.
