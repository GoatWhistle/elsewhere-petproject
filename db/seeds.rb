# Rebuilds the curated corpus from pages already on disk. Deliberately offline: `db:seed` runs inside
# `db:prepare`, and a seed task must never quietly start a web harvest. To collect pages in the first place:
#
#   bin/rails runner 'puts Supply::Corpus.seed!(offline: false, log: ->(l) { puts l })'
#
require_relative "../packs/supply/lib/supply"

summary = Supply::Corpus.seed!(log: ->(line) { puts line })
puts summary

coverage = Supply::Corpus.coverage
puts "geography: #{coverage["geography"].map { |type, n| "#{type}=#{n}" }.join(" ")}"
puts "gaps: #{coverage["gaps"].empty? ? "none" : coverage["gaps"].join("; ")}"
