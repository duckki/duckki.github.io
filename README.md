# Love Formal

Source for [duckki.github.io](https://duckki.github.io/), a personal Jekyll blog about software engineering, programming languages, program analysis, and formal verification.

## Local development

The repository uses direct, locked Jekyll, Minima, and plugin dependencies. The
publishing workflow builds the site itself instead of using GitHub Pages' bundled
Jekyll environment.

1. Install Ruby from `.ruby-version` and Node.js from `.nvmrc`.
2. Install dependencies with `bundle install` and `npm ci`.
3. Start the site with `bundle exec jekyll serve --livereload`.
4. Open <http://127.0.0.1:4000/>.

Drafts belong in `_drafts/`. Preview them with:

```sh
bundle exec jekyll serve --drafts --livereload
```

Local notes that should never be published belong in `.scratch/`.

## Checks

```sh
npm run lint
JEKYLL_ENV=production bundle exec rake test
```

`bundle exec rake links` additionally checks external links and is run by the scheduled link-check workflow.

## Publishing

Pull requests build and validate the site without deploying it. A push to `main` builds the same source and publishes the generated artifact through GitHub Pages.
