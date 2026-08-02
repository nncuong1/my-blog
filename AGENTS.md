## Development

When starting the dev server, use background mode:

```
astro dev --background
```

Manage the background server with `astro dev stop`, `astro dev status`, and `astro dev logs`.

## Agent instruction files

Claude Code and Codex read per-directory instructions under different names —
`CLAUDE.md` and `AGENTS.md`. So every folder that has rules keeps **one real
`AGENTS.md` plus a `CLAUDE.md` symlink pointing at it**. One file, two names,
nothing to keep in sync. A file's rules apply to its own directory and
everything below it; deeper files win on conflict.

**Always edit `AGENTS.md`, never the `CLAUDE.md` symlink.** Some editors save by
writing a temp file and renaming it over the target, which replaces the symlink
with a regular file — after that the two names have separate contents and drift
apart silently.

### Adding rules for a new topic folder

Say a new `src/content/posts/k8s/` series:

```
cd src/content/posts/k8s
# write the rules in AGENTS.md, then:
ln -s AGENTS.md CLAUDE.md
git add AGENTS.md CLAUDE.md
```

The symlink target is relative (`AGENTS.md`, not a full path) so it survives a
clone to any directory.

### Converting an existing CLAUDE.md

```
git mv <dir>/CLAUDE.md <dir>/AGENTS.md
ln -s AGENTS.md <dir>/CLAUDE.md
git add <dir>/CLAUDE.md
```

Then fix any prose in the file that referred to the old filename.

### Verifying

```
find . -name CLAUDE.md -not -type l -not -path './node_modules/*'   # must print nothing
git ls-files -s '*CLAUDE.md'                                        # every row must be mode 120000
```

Mode `120000` is git's symlink mode. A `100644` there means git stored a full
copy instead of a link, and that copy will drift from `AGENTS.md` for everyone
who clones — even though the two look linked on your own machine.

## Documentation

Full documentation: https://docs.astro.build

Consult these guides before working on related tasks:

- [Adding pages, dynamic routes, or middleware](https://docs.astro.build/en/guides/routing/)
- [Working with Astro components](https://docs.astro.build/en/basics/astro-components/)
- [Using React, Vue, Svelte, or other framework components](https://docs.astro.build/en/guides/framework-components/)
- [Adding or managing content](https://docs.astro.build/en/guides/content-collections/)
- [Adding styles or using Tailwind](https://docs.astro.build/en/guides/styling/)
- [Supporting multiple languages](https://docs.astro.build/en/guides/internationalization/)
