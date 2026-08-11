---
layout: default
title: "Software and formal methods notes"
description: "Software engineering, programming languages, formal verification, and everything in between."
---

<section class="hero">
  <p class="eyebrow">A personal notebook by Duckki Oe</p>
  <h1>Software engineering, programming languages, formal verification, and everything in between.</h1>
  <p class="hero__lede">I write about the ideas and tools that help us understand software more precisely—from language design and program analysis to mechanized models and verified systems.</p>
  <div class="hero__actions">
    <a class="button button--primary" href="#latest">Read the latest</a>
    <a class="button" href="{{ '/archive.html' | relative_url }}">Browse the archive</a>
  </div>
</section>

<section class="latest-posts" id="latest" aria-labelledby="latest-heading">
  <div class="section-heading">
    <div>
      <p class="eyebrow">From the notebook</p>
      <h2 id="latest-heading">Latest essays</h2>
    </div>
    <a href="{{ '/feed.xml' | relative_url }}">Subscribe via RSS →</a>
  </div>

  <div class="post-grid">
    {%- for post in site.posts -%}
      <article class="post-card">
        <div class="post-card__meta">
          <time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: "%b %-d, %Y" }}</time>
          {%- if post.tags.size > 0 -%}
            <span>{{ post.tags | first }}</span>
          {%- endif -%}
        </div>
        <h3><a href="{{ post.url | relative_url }}">{{ post.title | escape }}</a></h3>
        <p>{{ post.description | default: post.excerpt | strip_html | normalize_whitespace | truncatewords: 30 }}</p>
        <a class="post-card__link" href="{{ post.url | relative_url }}" aria-label="Read {{ post.title | escape }}">Read essay <span aria-hidden="true">→</span></a>
      </article>
    {%- endfor -%}
  </div>
</section>
