require "html-proofer"
require "rake"

SITE_DIR = "./_site"
GRAPHQL_DIRECTIVE_POST = File.join(
  SITE_DIR,
  "2026/08/30/static-analysis-for-graphql-verified-in-lean.html",
)
SHARE_URLS = [
  %r{linkedin\.com/sharing/share-offsite},
].freeze
EXTERNAL_IGNORE_URLS = SHARE_URLS + [
  %r{^https://duckki\.github\.io(?:/|$)},
  %r{linkedin\.com},
  %r{stackoverflow\.com},
]

def prove_site(options)
  proofer = HTMLProofer.check_directory(SITE_DIR, options)
  proofer.run
  return if proofer.failed_checks.empty?

  raise "HTML-Proofer found #{proofer.failed_checks.length} failure(s)"
end

desc "Build the production site"
task :build do
  sh "bundle exec jekyll build --strict_front_matter --trace"
end

desc "Validate generated HTML and internal links"
task proof: :build do
  prove_site(
    disable_external: true,
    enforce_https: true,
    check_internal_hash: true,
    ignore_urls: SHARE_URLS,
  )
end

desc "Check custom GraphQL highlighting"
task highlighting: :build do
  html = File.read(GRAPHQL_DIRECTIVE_POST)
  expected = [
    '<span class="nd">@cost</span>',
    '<span class="s2">"2"</span><span class="p">)</span>',
    '<span class="nl">label</span><span class="p">:</span>',
  ]
  broken = [
    '<span class="err">@</span><span class="n">cost</span>',
    '<span class="err">"2")</span>',
  ]

  unless expected.all? { |markup| html.include?(markup) } &&
      broken.none? { |markup| html.include?(markup) }
    raise "GraphQL syntax was not highlighted correctly"
  end
end

desc "Validate generated HTML and external links"
task links: :build do
  prove_site(
    enforce_https: true,
    check_external_hash: false,
    ignore_status_codes: [403, 429],
    ignore_urls: EXTERNAL_IGNORE_URLS,
    typhoeus: {
      connecttimeout: 10,
      timeout: 30,
      followlocation: true,
    },
  )
end

desc "Run the deterministic site checks"
task test: [:proof, :highlighting]

task default: :test
