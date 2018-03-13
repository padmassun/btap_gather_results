#!/usr/bin/env ruby
# CLI tool to allow for creating a version of the localResults directory on the server
# This should be employed as a server finalizations script for BuildStock PAT projects
# Written by Henry R Horsey III (henry.horsey@nrel.gov)
# Created October 5th, 2017
# Last updated on October 6th, 2017
# Copywrite the Alliance for Sustainable Energy LLC
# License: BSD3+1

require 'rest-client'
require 'fileutils'
require 'zip'
require 'parallel'
require 'optparse'

# Unzip an archive to a destination directory using Rubyzip gem
#
# @param archive [:string] archive path for extraction
# @param dest [:string] path for archived file to be extracted to
def unzip_archive(archive, dest)
  # Adapted from examples at...
  # https://github.com/rubyzip/rubyzip
  # http://seenuvasan.wordpress.com/2010/09/21/unzip-files-using-ruby/
  Zip::File.open(archive) do |zf|
    zf.each do |f|
      f_path = File.join(dest, f.name)
      if (f.name == 'enduse_timeseries.csv') || (f.name == 'measure_attributes.json')
        FileUtils.mkdir_p(File.dirname(f_path))
        zf.extract(f, f_path) unless File.exist?(f_path) # No overwrite
      end
    end
  end
end

# Gather the required files from each zip file on the server for an analysis
#
# @param aid [:string] analysis uuid to retrieve files for
# @param num_cores [:int] available cores to the executing agent
def gather_output_results(aid, num_cores=1)
  # Ensure required directories exist and create if appropriate
  basepath = '/mnt/openstudio/server/assets/data_points'
  unless Dir.exists? basepath
    fail "ERROR: Unable to find base data point path #{basepath}"
  end
  resultspath = "/mnt/results/#{aid}"
  unless Dir.exists? resultspath
    FileUtils.mkdir_p resultspath
  end

  # Determine all data points to download from the REST API
  astat = JSON.parse RestClient.get("http://web:80/analyses/#{aid}/status.json", headers={})
  dps = astat['analysis']['data_points'].map { |dp| dp['id'] }

  # Ensure there are datapoints to download
  if dps.nil? || dps.empty?
    fail "ERROR: No datapoints found. Analysis #{aid} completed with no datapoints"
  end

  # Find all data points asset ids
  assetids = {}
  dps.each do |dp|
    begin
      dp_res_files = JSON.parse(RestClient.get("http://web:80/data_points/#{dp}.json", headers={}))['data_point']['result_files']
      if dp_res_files.nil?
        puts "Unable to find related files for data point #{dp}"
      else
        zips = dp_res_files.select { |file| file['attachment_content_type'] == 'application/zip' }
        if zips.empty?
          puts "No zip files found attached to data point #{dp}"
        elsif zips.length > 1
          puts "More than one zip file is attached to data point #{dp}, skipping"
        else
          assetids[dp] = zips[0]['_id']['$oid']
        end
      end
    rescue RestClient::ExceptionWithResponse
      puts "Unable to retrieve json from REST API for data point #{dp}"
    end
  end

  # Register and remove missing datapoint zip files
  available_dps = Dir.entries basepath
  missing_dps = []
  dps.each { |dp| missing_dps << dp unless available_dps.include? assetids[dp] }
  puts "Missing #{100.0 * missing_dps.length.to_f / dps.length}% of data point zip files"
  unless missing_dps.empty?
    logfile = File.join resultspath, 'missing_dps.log'
    puts "Writing missing datapoint UUIDs to #{logfile}"
    File.open(logfile, 'wb') do |f|
      f.write JSON.dump(missing_dps)
    end
  end

  # Only download datapoints which do not already exist
  exclusion_list = Dir.entries resultspath
  Parallel.each(assetids.keys, progress: 'Assembled:', in_processes: (num_cores * 2)) do |dp|
    unless (exclusion_list.include? dp) || (missing_dps.include? dp)
      zip_file = File.join(basepath, assetids[dp], 'files', 'original', 'data_point.zip')
      write_dir = File.join(resultspath, dp)
      Dir.mkdir write_dir unless Dir.exists? write_dir
      unzip_archive zip_file, write_dir
    end
  end
end

# Initialize optionsParser ARGV hash
options = {}

# Define allowed ARGV input
# -a --analysis_id [string]
# -n --num_cores [string]
optparse = OptionParser.new do |opts|
  opts.banner = 'Usage:    gather_results [-a] <analysis_id> [-n] <num_cores> -h]'

  options[:analysis_id] = nil
  opts.on('-a', '--analysis_id <uuid>', 'specified analysis UUID') do |uuid|
    options[:analysis_id] = uuid
  end

  options[:num_cores] = 1
  opts.on('-n', '--num_cores <INT>', 'number of available CORES') do |cores|
    options[:num_cores] = cores
  end

  opts.on_tail('-h', '--help', 'display help') do
    puts opts
    exit
  end
end

# Execute ARGV parsing into options hash holding symbolized key values
optparse.parse!

# Sanity check inputs
fail 'analysis UUID not specified' if options[:analysis_id].nil?
fail 'enter a number of avaialble cores greater than zero' if options[:num_cores].to_i == 0

# Gather the required files
Zip.warn_invalid_date = false
gather_output_results(options[:analysis_id], options[:num_cores])

# Finish up
puts 'SUCCESS'

