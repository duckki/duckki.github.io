---
layout: page
title: "Essay archive"
description: "All Love Formal essays, organized by year."
permalink: /archive.html
---

<p class="page-intro">A chronological notebook on software engineering, programming languages, program analysis, formal verification, and everything in between.</p>

<div class="archive-list">
  {%- assign current_year = "" -%}
  {%- for post in site.posts -%}
    {%- assign post_year = post.date | date: "%Y" -%}
    {%- if post_year != current_year -%}
      {%- unless forloop.first -%}</div>{%- endunless -%}
      <div class="archive-year">
        <h2>{{ post_year }}</h2>
      {%- assign current_year = post_year -%}
    {%- endif -%}
        <article class="archive-entry">
          <time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: "%b %-d" }}</time>
          <div>
            <h3><a href="{{ post.url | relative_url }}">{{ post.title | escape }}</a></h3>
            <p>{{ post.description | escape }}</p>
          </div>
        </article>
    {%- if forloop.last -%}</div>{%- endif -%}
  {%- endfor -%}
</div>
