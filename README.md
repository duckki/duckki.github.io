# PL Rant

Source for [duckki.github.io](https://duckki.github.io/), a Jekyll blog about programming languages and static analysis.

## Local development

The repository uses the same `github-pages` dependency bundle as the hosted site.

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
bundle exec rake test
npm run lint
```

`bundle exec rake links` additionally checks external links and is run by the scheduled link-check workflow.

## Publishing

Pull requests build and validate the site without deploying it. A push to `main` builds the same source and publishes the generated artifact through GitHub Pages.
