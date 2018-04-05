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
require 'json'
require 'base64'

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
  resultspath = "/mnt/openstudio/server/assets/results/osw_files/"
  outputpath = "/mnt/openstudio/server/assets/results/"

  simulations_json_folder = outputpath
FileUtils.mkdir_p(outputpath)
osw_folder = "#{outputpath}/osw_files"
FileUtils.mkdir_p(osw_folder)
output_folder = "#{outputpath}/output"
FileUtils.mkdir_p(output_folder)
File.open("#{outputpath}/missing_files.log", 'wb') { |f| f.write("") }
File.open("#{outputpath}/missing_files.log", 'w') {|f| f.write("") }
File.open("#{simulations_json_folder}/simulations.json", 'w'){}

  puts "creating results folder #{resultspath}"
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
      puts dp_res_files
      if dp_res_files.nil?
        puts "Unable to find related files for data point #{dp}"
      else
        osws = dp_res_files.select { |file| file['attachment_file_name'] == "out.osw" }
        if osws.empty?
          puts "No osw files found attached to data point #{dp}"
        elsif osws.length > 1
          puts "More than one osw file is attached to data point #{dp}, skipping"
        else
          assetids[dp] = osws[0]['_id']['$oid']
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
  
  assetids.keys.each do |dp|
    unless (exclusion_list.include? dp) || (missing_dps.include? dp)
      puts dp
      uuid = dp
      #OSW file name
      osw_file = File.join(basepath, assetids[dp], 'files', 'original', 'out.osw')
      #The folder path with the UUID of the datapoint in the path. 
      write_dir = File.join(resultspath, dp)
      #Makes the folder for the datapoint. 
      FileUtils.mkdir_p write_dir unless Dir.exists? write_dir
      #Gets the basename from the full path of of the osw file (Should always be out.osw) 
      osw_basename = File.basename(osw_file)
      #Create the new osw file name name. 
      new_osw = "#{write_dir}/#{osw_basename}"
      puts new_osw
      #This is the copy command to copy the osw_file to the new results folder. 
      FileUtils.cp(osw_file,"#{write_dir}/#{osw_basename}")

      results = JSON.parse(File.read(osw_file))
     
      # change the output folder directory based on building_type and climate_zone
      # get building_type and climate_zone from create_prototype_building measure if it exists
      results['steps'].each do |measure|
        next unless measure["name"] == "btap_create_necb_prototype_building"
        #template = measure["arguments"]["template"]
        building_type = measure["arguments"]["building_type"]
        #climate_zone = measure["arguments"]["climate_zone"]
        #remove the .epw suffix
        epw_file = measure["arguments"]["epw_file"].gsub(/\.epw/,"")
        output_folder = "#{outputpath}/output/#{building_type}/#{epw_file}"
        #puts output_folder
        FileUtils.mkdir_p(output_folder)
      end
       
         #parse the downloaded osw files and check if the datapoint failed or not
      #if failed download the eplusout.err and sldp_log files for error logging
      failed_log_folder = "#{output_folder}/failed_run_logs"
     # check_and_log_error(results,outputpath,uuid,failed_log_folder)

      #itterate through all the steps of the osw file
          results['steps'].each do |measure|
            #puts "measure.name: #{measure['name']}"
            found_osm = false
            found_json = false

            # if the measure is openstudioresults, then download the eplustbl.htm and the pretty report [report.html]
            if measure["name"] == "openstudio_results" && measure.include?("result")
              measure["result"]["step_values"].each do |values|
                # extract the eplustbl.html blob data from the osw file and save it
                # in the output folder
                if values["name"] == 'eplustbl_htm'
                  eplustbl_htm_zip = values['value']
                  eplustbl_htm_string =  Zlib::Inflate.inflate(Base64.strict_decode64( eplustbl_htm_zip ))
                  FileUtils.mkdir_p("#{output_folder}/eplus_table")
                  File.open("#{output_folder}/eplus_table/#{uuid}-eplustbl.htm", 'wb') {|f| f.write(eplustbl_htm_string) }
                  #puts "#{uuid}-eplustbl.htm ok"
                end
                # extract the pretty report.html blob data from the osw file and save it
                # in the output folder
                if values["name"] == 'report_html'
                  report_html_zip = values['value']
                  report_html_string =  Zlib::Inflate.inflate(Base64.strict_decode64( report_html_zip ))
                  FileUtils.mkdir_p("#{output_folder}/os_report")
                  File.open("#{output_folder}/os_report/#{uuid}-os-report.html", 'wb') {|f| f.write(report_html_string) }
                  #puts "#{uuid}-os-report.html ok"
                end
              end
            end

            # if the measure is view_model, then extract the 3d.html model and save it
            if measure["name"] == "btap_view_model" && measure.include?("result")
              measure["result"]["step_values"].each do |values|
                if values["name"] == 'view_model_html_zip'
                  view_model_html_zip = values['value']
                  view_model_html =  Zlib::Inflate.inflate(Base64.strict_decode64( view_model_html_zip ))
                  FileUtils.mkdir_p("#{output_folder}/3d_model")
                  File.open("#{output_folder}/3d_model/#{uuid}_3d.html", 'wb') {|f| f.write(view_model_html) }
                  #puts "#{uuid}-eplustbl.htm ok"
                end
              end
            end

            # if the measure is btapresults, then extract the osw file and qaqc json
            # While processing the qaqc json file, add it to the simulations.json file
            if measure["name"] == "btap_results" && measure.include?("result")
              measure["result"]["step_values"].each do |values|
                # extract the model_osm_zip blob data from the osw file and save it
                # in the output folder
                if values["name"] == 'model_osm_zip'
                  found_osm = true
                  model_osm_zip = values['value']
                  osm_string =  Zlib::Inflate.inflate(Base64.strict_decode64( model_osm_zip ))
                  FileUtils.mkdir_p("#{output_folder}/osm_files")
                  File.open("#{output_folder}/osm_files/#{uuid}.osm", 'wb') {|f| f.write(osm_string) }
                  #puts "#{uuid}.osm ok"
                end

                # extract the btap_results_hourly_data_8760 blob data from the osw file and save it
                # in the output folder
                if values["name"] == 'btap_results_hourly_data_8760'
                  model_osm_zip = values['value']
                  osm_string =  Zlib::Inflate.inflate(Base64.strict_decode64( model_osm_zip ))
                  FileUtils.mkdir_p("#{output_folder}/8760_files")
                  File.open("#{output_folder}/8760_files/#{uuid}-8760_hourly_data.csv", 'w+') {|f| f.write(osm_string) }
                  #puts "#{uuid}.osm ok"
                end

                # extract the btap_results_hourly_custom_8760 blob data from the osw file and save it
                # in the output folder
                if values["name"] == 'btap_results_hourly_custom_8760'
                  model_osm_zip = values['value']
                  osm_string =  Zlib::Inflate.inflate(Base64.strict_decode64( model_osm_zip ))
                  FileUtils.mkdir_p("#{output_folder}/8760_files")
                  File.open("#{output_folder}/8760_files/#{uuid}-8760_hour_custom.csv", 'w+') {|f| f.write(osm_string) }
                  #puts "#{uuid}.osm ok"
                end

                # extract the btap_results_monthly_7_day_24_hour_averages blob data from the osw file and save it
                # in the output folder
                if values["name"] == 'btap_results_monthly_7_day_24_hour_averages'
                  model_osm_zip = values['value']
                  osm_string =  Zlib::Inflate.inflate(Base64.strict_decode64( model_osm_zip ))
                  FileUtils.mkdir_p("#{output_folder}/8760_files")
                  File.open("#{output_folder}/8760_files/#{uuid}-mnth_24_hr_avg.csv", 'w+') {|f| f.write(osm_string) }
                  #puts "#{uuid}.osm ok"
                end

                # extract the btap_results_monthly_24_hour_weekend_weekday_averages blob data from the 
                #osw file and save it in the output folder
                if values["name"] == 'btap_results_monthly_24_hour_weekend_weekday_averages'
                  model_osm_zip = values['value']
                  osm_string =  Zlib::Inflate.inflate(Base64.strict_decode64( model_osm_zip ))
                  FileUtils.mkdir_p("#{output_folder}/8760_files")
                  File.open("#{output_folder}/8760_files/#{uuid}-mnth_weekend_weekday.csv", 'w+') {|f| f.write(osm_string) }
                  #puts "#{uuid}.osm ok"
                end

                # extract the btap_results_enduse_total_24_hour_weekend_weekday_averages blob data 
                # from the osw file and save it in the output folder
                if values["name"] == 'btap_results_enduse_total_24_hour_weekend_weekday_averages'
                  model_osm_zip = values['value']
                  osm_string =  Zlib::Inflate.inflate(Base64.strict_decode64( model_osm_zip ))
                  FileUtils.mkdir_p("#{output_folder}/8760_files")
                  File.open("#{output_folder}/8760_files/#{uuid}-endusetotal.csv", 'w+') {|f| f.write(osm_string) }
                  #puts "#{uuid}.osm ok"
                end


                # extract the qaqc json blob data from the osw file and save it
                # in the output folder
                if values["name"] == 'btap_results_json_zip'
                  found_json = true
                  btap_results_json_zip = values['value']
                  json_string =  Zlib::Inflate.inflate(Base64.strict_decode64( btap_results_json_zip ))
                  json = JSON.parse(json_string)
                  # indicate if the current model is a baseline run or not
                  json['is_baseline'] = "#{flags[:baseline]}"

                  #add ECM data to the json file
                  measure_data = []
                  results['steps'].each_with_index do |measure, index|
                    step = {}
                    measure_data << step
                    step['name'] = measure['name']
                    step['arguments'] = measure['arguments']
                    if measure.has_key?('result')
                      step['display_name'] = measure['result']['measure_display_name']
                      step['measure_class_name'] = measure['result']['measure_class_name']
                    end
                    step['index'] = index
                    # measure is an ecm if it starts with ecm_ (case ignored)
                    step['is_ecm'] = !(measure['name'] =~ /^ecm_/i).nil? # returns true if measure name starts with 'ecm_' (case ignored)
                  end

                  json['measures'] = measure_data

                  FileUtils.mkdir_p("#{output_folder}/qaqc_files")
                  File.open("#{output_folder}/qaqc_files/#{uuid}.json", 'wb') {|f| f.write(JSON.pretty_generate(json)) }

                  # append qaqc data to simulations.json
                  process_simulation_json(json,simulations_json_folder, uuid)
                  puts "#{uuid}.json ok"
                end # values["name"] == 'btap_results_json_zip'
              end
            end # if measure["name"] == "btapresults" && measure.include?("result")
          end # of grab step files

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

