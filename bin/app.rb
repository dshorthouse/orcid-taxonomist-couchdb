#!/usr/bin/env ruby
# encoding: utf-8
require 'optparse'
require File.dirname(File.dirname(__FILE__)) + '/environment.rb'
config_file = File.join(File.dirname(File.dirname(__FILE__)), 'config.yml')

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: app.rb [options]"

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end

  opts.on("-e", "--environment [ENVIRONMENT]", String, "Include environment, defaults to development") do |env|
    options[:environment] = env
  end

  opts.on("-i", "--initialize", "Create the database and views in CouchDB") do
    options[:init] = true
  end

  opts.on("-c", "--config [FILE]", String, "Include a full path to the config.yml file") do |config|
    options[:config] = config
  end

  opts.on("-s", "--search", "Search for new records on ORCID") do
    options[:search] = true
  end

  opts.on("-w", "--works [DOIS]", Array, "Add ORCID records based on search for DOI of works") do |works|
    options[:works] = works
  end

  opts.on("-o", "--orcids [ORCIDS]", Array, "Update existing ORCID records or save new ones") do |orcids|
    options[:orcids] = orcids
  end

  opts.on("-d", "--delete [ORCID]", String, "Delete a single ORCID") do |orcid|
    options[:delete] = orcid
  end

  opts.on("-u", "--update", "Update all existing records") do
    options[:update] = true
  end
end.parse!

config_file = options[:config] if options[:config]
ENV["ENVIRONMENT"] = options[:environment].nil? ? "development" : options[:environment]
raise "Config file not found" unless File.exists?(config_file)

ot = OrcidTaxonomist.new({ config_file: config_file })

if options[:init]
  ot.create_design_document
  puts "Done".green
elsif options[:works]
  options[:works].each do |doi|
    ot.populate_taxonomists(doi)
  end
  ot.populate_taxa
  ot.write_webpage
  ot.write_csv
  puts "Done".green
elsif options[:orcids]
  options[:orcids].each do |orcid|
    ot.update_taxonomist(orcid)
  end
  ot.write_webpage
  ot.write_csv
  puts "Done".green
elsif options[:delete]
  ot.delete_taxonomist(options[:delete])
  ot.write_webpage
  ot.write_csv
  puts "Done".green
else
  if options[:search]
    ot.populate_taxonomists
    ot.populate_taxa
    ot.write_webpage
    ot.write_csv
    puts "Done".green
  end

  if options[:update]
    ot.update_taxonomists
    ot.write_webpage
    ot.write_csv
    puts "Done".green
  end
end
