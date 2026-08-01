# Repository Maintenance Instructions

These instructions apply to the entire `duckki.github.io` repository.

## Local-only files

- Ignore `.scratch/` and `.vscode/` completely unless the user explicitly asks
  to work with them. Do not inspect, modify, lint, stage, or publish their
  contents.
- Treat `.scratch/` as private, unpublished working material.
- Do not stage generated or dependency directories such as `_site/`, `vendor/`,
  or `node_modules/`.

## Project shape

- This is a GitHub Pages site built with Jekyll and the `minima` theme.
- Use the Ruby version in `.ruby-version`, the Node.js version in `.nvmrc`, and
  the committed Bundler and npm lock files. Do not replace the lock files or
  upgrade broad dependency sets unless the task calls for it.
- Published posts live in `_posts/` and use `YYYY-MM-DD-slug.md` filenames.
  Preserve the existing front matter fields: `title`, `date`, `description`,
  and `tags`.
- Prefer Jekyll helpers such as `{% post_url ... %}` for links between posts.
- Keep `_config.yml` exclusions aligned with `.gitignore` when adding local-only
  tooling or files.

## Theme maintenance

- The intentional visual baseline is VS Code Dark Modern, implemented in
  `css/override.css`. Preserve the always-dark presentation unless the user
  requests a redesign or light theme.
- Important established colors and treatments are:
  - page and code-block background: `#1f1f1f`
  - body text: `#cccccc`
  - generic code identifiers: `#d4d4d4`
  - operators: soft magenta `#c586c0`
  - inline-code background: subtle `#292929`
- Keep function names normal weight, not bold. Inline code should have no
  border, rounded box, or strong highlight. Generic identifiers should remain
  readable even when Rouge does not distinguish locals, types, and other names.
- After CSS or layout changes, inspect at least one post with Rust code plus the
  home and archive pages, including a narrow/mobile viewport.

## Analytics

- Cloudflare Web Analytics is configured in `_config.yml` and emitted by
  `_includes/analytics.html` through the footer.
- The beacon must remain production-only. A normal local development build must
  not contain the Cloudflare beacon script; a build with `JEKYLL_ENV=production`
  should include the beacon once per generated HTML page.
- The Cloudflare beacon token is a public site identifier. Never place API
  tokens, account credentials, or other secrets in the site or repository.

## Local preview

- Install dependencies with `bundle install` and `npm ci` when needed.
- Use this preview command by default:

  ```sh
  bundle exec jekyll serve --livereload --host 127.0.0.1 --port 4000
  ```

- Open `http://127.0.0.1:4000/`. Use `--drafts` only when the user explicitly
  wants Jekyll `_drafts/` included.
- If the user asks to keep the server running, start it in a long-lived
  background/PTY session, verify the URL responds, and leave it running until
  asked to stop. Check an occupied port before starting or killing anything;
  never terminate an unrelated process.
- Local preview intentionally omits analytics because it is not a production
  Jekyll environment.

## Verification

Run checks proportional to the change. Before publishing, run the complete
deterministic set:

```sh
npm run lint
JEKYLL_ENV=production bundle exec rake test
git diff --check
```

- `bundle exec rake test` builds with strict front matter and runs HTML-Proofer
  against generated HTML and internal links.
- Use `bundle exec rake links` when changing external links or investigating the
  scheduled link-check workflow. It contacts third-party sites and may encounter
  transient rate limits, so it is not part of every local change.
- For analytics changes, additionally compare development and production output
  for the Cloudflare beacon.

## Review, commit, and publishing workflow

- Work carefully with any existing user changes. Stage only files belonging to
  the current reviewed slice.
- Do not commit before review. Prepare the change, run relevant checks, summarize
  the exact diff, and wait for the user to request a commit.
- If the user requests only `commit`, create a terse, intentional commit and stop
  before pushing. If the user explicitly requests `push`, `publish`, or
  `commit & push`, continue through the requested push.
- The publishing branch is `main`. A push to `main` triggers
  `.github/workflows/pages.yml`, which lints content, builds and validates the
  production site, uploads `_site` as a Pages artifact, and deploys it. Never
  commit or manually upload `_site`.
- Pull requests run validation but intentionally skip artifact upload and Pages
  deployment.
- After pushing a publishing change, monitor the `Build and deploy site` run to
  completion. Confirm all jobs succeed and inspect warning annotations when the
  change concerns Actions or runtimes. Use `gh` when authenticated; because the
  repository is public, the GitHub REST API is an acceptable read-only fallback.
- Verify the live site at `https://duckki.github.io/` after deployment when the
  change affects generated output. For analytics work, confirm the production
  HTML contains the beacon exactly once.
- Keep GitHub Actions on supported runtime majors. The workflow currently uses
  Node 24-compatible action majors; do not suppress runtime deprecation warnings
  with compatibility flags or confuse an action's internal Node runtime with the
  `.nvmrc` version used by this project's tooling.
- Never force-push, amend published commits, or rewrite `main` unless the user
  explicitly requests it and the implications have been reviewed.
