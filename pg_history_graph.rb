require 'open-uri'
require 'nokogiri'
require 'optparse'
require 'date'

require './pgversion.rb'

PgReleasesURL = 'https://www.postgresql.org/docs/devel/static/release.html'
ReleasesFilename = 'releases'
ReleasesFilepath = $ReleaseNoteDir + "/" + ReleasesFilename
MajorsFilename = 'majores'
MajorsFilepath = $ReleaseNoteDir + "/" + MajorsFilename
PG_MIN_VERSION = 6
OUTPUT_FORMAT = "%-7s%-7s"

pgversions = []
never_pgversions = []
major_versions = {}
major_ver_list = []

# Variables for option
reload = false
header_line_interval = 20
version_from = 8

opt = OptionParser.new
opt.on('-r', '--reload', 'reload all release note data') { reload = true }
opt.on('-i NUM', '--interval=NUM', 'header line interval') { |v| header_line_interval = v.to_i}
opt.on('-v NUM', '--version=NUM', 'Output releases from NUM version') { |v| version_from = v.to_i }
opt.parse(ARGV)

def reload_pgversions()
  # Get all version and create PgVersion instances
  release_doc = Nokogiri::HTML(open(PgReleasesURL))

  # Open release version file
  releases_file = File.open(ReleasesFilepath, "w")
  majors_file = File.open(MajorsFilepath, "w")
  
  release_doc.xpath("//span[@class='sect1' and contains (*, 'Release')]").each do |t|
    ver_match = t.inner_text.match(/[0-9]+\.[0-9]+\.*[0-9]*/)

    # Retry for version 10 or later
    # XXX: need to fix it after version 11 released
    if ver_match.nil? then
      ver_match = t.inner_text.match(/10\.*[0-9]*/)
    end

    # This line is not any version, skip it
    if ver_match.nil? then next end
  
    version = ver_match[0]

    # Only support for pg_min_version or later
    if version.split('.')[0].to_i < PG_MIN_VERSION then next end

    # Generate PgVersion instances
    pv = PgVersion.new(version, false)

    # Save relase note source html data if not exist
    if !pv.exist? then 
      pv.save_release_note()
    end

    # Save release version data
    releases_file.puts(pv.version)
    # Save major versions data
    if pv.first_version then
      majors_file.puts(pv.version)
    end
  end
end

# Reload files if needed
if reload then reload_pgversions() end

# Check if there are necessary files
cannot_execute = false
if !File.exist?(ReleasesFilepath) then
  puts "\"" + ReleasesFilepath + "\" doesn't exist"
  cannot_execute = ture
end
if !File.exist?(MajorsFilepath) then
  puts "\"" + MajorsFilepath + "\" doesn't exist"
  cannot_execute = ture
end

if cannot_execute then
  puts "Reloading information by " + __FILE__ + " -r might be needed."
  exit
end

# Load from file and construct PgVersion array
File.open(ReleasesFilepath, "r") do |f|
  # Iterate each versions
  f.each_line do |version|

    # Generate PgVersion instances
    pv = PgVersion.new(version.chomp(), true)

    # Skip release older than the threshold(version_from)
    if pv.version_1.to_i < version_from then next end

    # It can happen a version is never released. In this case, we store it
    # to an another array never_pgversion.
    if pv.release_date == "never released" then
      never_pgversions << p
      next
    end

    # Here, we have only *released' pgversions. We insert them to the array
    # in date and version asc order for the later use.
    if pgversions.empty? then
      pgversions << pv
    elsif
      release_date = pv.release_date
      pgversions.each_with_index do |pv_elem, i|
        release_date_elem = pv_elem.release_date

        if release_date_elem >= release_date and pv_elem.version_num > pv.version_num then
          pgversions.insert(i, pv)
          break
        end
      end
    end
  end

  # We prepare an another hash table for major versions.
  pgversions.each do |pv|

    # Skip release older than the threshold(version_from).
    if pv.version_1.to_i < version_from then next end

    # Make major version.
    if pv.version_1.to_i >= 10 then
      major_version = pv.version_1
    else
      major_version = pv.version_1 + "." + pv.version_2
    end

    major_pv = major_versions[major_version]
    if major_pv.nil? then
      # Create new major version instance.
      major_pv = PgMajorVersion.new(major_version)
      major_versions[major_version] = major_pv
    end

    # append pv to major version group as one release.
    major_pv.minor_versions << pv
    major_pv.set_max_minor_ver()
  end
end

# Load major versions.
File.open(MajorsFilepath, "r") do |f|
  f.each_line do |major_ver|
    major_ver_list.insert(0, major_ver.chomp)
  end
end

# Make output header.
header_line = sprintf("%-13s", "Date")
major_ver_list.each do |ver|
  # Skip release older than the threshold(version_from).
  if ver.split('.')[0].to_i < version_from then next end

  header_line = sprintf(OUTPUT_FORMAT, header_line, ver)
end
header_line.gsub!(/\ |\t/, "-")

# Put the header line on the top.
puts header_line

# Main routine for writing the version history graph.
prev_date = nil
output_count = 0
pgversions.each do |pv|
  current_date = pv.release_date
  buf = sprintf("%-14s", current_date.strftime('%Y-%m-%d'))

  if prev_date != current_date then
    # Iterate all major versions.
    major_ver_list.each do |major_ver|

      # Fetch pgMajorVersion from hash table entry.
      major_pv = major_versions[major_ver]

      # If we ignored some major version due to version_from, major_pv can be nil.
      if major_pv.nil? then next end

      # Ask MajorVersion; Do you have a minor version that is released at current_date?
      released_pv = major_pv.get_released_version(current_date)

      if released_pv.nil? then
        # this major version is not released at current_date
        if major_pv.started then
          char = ":"
        else
          char = " "
        end
        buf = sprintf(OUTPUT_FORMAT, buf, char)
      else
        # thie minor versions is relaesed
        buf = sprintf(OUTPUT_FORMAT, buf, released_pv.get_minor_version)

        if released_pv.get_minor_version == "0" and
            released_pv.get_minor_version != major_pv.max_minor_ver.to_s then
          # This series of major version released at current_date.
          major_pv.started = true
        elsif released_pv.get_minor_version == major_pv.max_minor_ver.to_s then
          # This is the end of series of this major version.
          major_pv.started = false
        end
      end
    end

    # Output the prepared buf
    puts buf

    # Process header line interval
    output_count = output_count + 1
    if output_count >= header_line_interval then
      # Put the additional interval header line
      puts header_line
      output_count = 0
    end
  end

  prev_date = current_date
end
