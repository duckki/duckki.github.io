---
layout: default
title: "Programming language notes"
description: "Essays about language design, ownership, type systems, and static analysis."
---

<section class="hero">
  <p class="eyebrow">Programming languages · Static analysis</p>
  <h1>Language design, ownership, and the proofs between.</h1>
  <p class="hero__lede">Essays by Duckki Oe on the rules underneath software: how languages express intent, how references behave, and how static analysis can make those guarantees precise.</p>
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
