require 'nokogiri'
require 'open-uri'

$ReleaseNoteDir = './release_notes'
# for version 9.6 or before
PgReleaseURLBase_ThreeNum = "https://www.postgresql.org/docs/devel/static/release-XX-YY-ZZ.html"
PgReleaseURLBase_Fist_ThreeNum = "https://www.postgresql.org/docs/devel/static/release-XX-YY.html"
# for version 10 or later
PgReleaseURLBase_TwoNum = "https://www.postgresql.org/docs/devel/static/release-XX-YY.html"
PgReleaseURLBase_Fist_TwoNum = "https://www.postgresql.org/docs/devel/static/release-XX.html"

class PgMajorVersion
  attr_accessor :major_version, :minor_versions, :started, :max_minor_ver
  def initialize(version)
    @major_version = version
    @minor_versions = []
    @started = false
    @max_minor_ver = 0
  end

  # Get PgVersion that is released at the given date. Return nil if not have.
  def get_released_version(date)
    @minor_versions.each do |pv|
      if pv.release_date == date then
        return pv
      end
    end
    return nil
  end

  def set_max_minor_ver()
    max_ver = 0
    @minor_versions.each do |pv|
      if pv.get_minor_version.to_i > max_ver.to_i then
        max_ver = pv.get_minor_version.to_i
      end
    end
    @max_minor_ver = max_ver
  end
end

class PgVersion
  attr_accessor :version, :version_num, :version_1, :version_2, :version_3, :first_version, :release_date

  def initialize(version, set_release_date)
    @version = version
    @version_1 = version.split('.')[0]
    @version_2 = version.split('.')[1]
    @version_3 = version.split('.')[2]

    if @version_1.to_i >= 10 then
      # version 10 or later
      if @version_2.nil? then
        @first_version = true
        @version_num = sprintf("%02d0000", @version_1)
      else
        @first_version = false
        @version_num = sprintf("%02d00%02d", @version_1, @version_2)
      end
    else
      # version 9.6 or before
      if @version_3.nil? then
        @first_version = true
        @version_num = sprintf("%02d%02d00", @version_1, @version_2)
      else
        @first_version = false
        @version_num = sprintf("%02d%02d%02d", @version_1, @version_2, @version_3)
      end
    end

    if @version_1.to_i >= 10 then
      if @first_version then
        @release_note_url = PgReleaseURLBase_Fist_TwoNum.sub(/XX/, @version_1)
      else
        @release_note_url = PgReleaseURLBase_TwoNum.sub(/XX/, @version_1).sub(/YY/, @version_2)
      end
    else
      if @first_version then
        @release_note_url = PgReleaseURLBase_Fist_ThreeNum.sub(/XX/, @version_1).sub(/YY/, @version_2)
      else
        @release_note_url = PgReleaseURLBase_ThreeNum.sub(/XX/, @version_1).sub(/YY/, @version_2).sub(/ZZ/, @version_3)
      end
    end

    @r_note_filename = @version + ".html"
    @r_note_filepath = $ReleaseNoteDir + "/" + @r_note_filename

    
    # The release note date could not exist yet, we set this only if set_release_date is true
    @release_date = nil
    if set_release_date then
      File.open(@r_note_filepath, "r") do |f|
        r_note = Nokogiri::HTML.parse(f.read)

        r_date = r_note.xpath("//p[contains (*, 'Release date')]/text()").text
        if r_date != "never released" then
          @release_date = Time.strptime(r_note.xpath("//p[contains (*, 'Release date')]/text()").text, '%Y-%m-%d')
        else
          @release_date = r_date
        end
      end
    end
  end

  # Already release note file exists?
  def exist?()
    return File.exist?(@r_note_filepath)
  end

  # Save release note html file into ReleaseNoteDir
  def save_release_note()
    puts "Saving the release note of " + @version + " ..."
    r_note = Nokogiri::HTML(open(@release_note_url))
    File.open(@r_note_filepath, "w") do |f|
      f.puts(r_note)
    end
  end

  def get_minor_version()
    if @first_version then
      return "0"
    else
      if @version_1.to_i >= 10 then
        return @version_2
      else
        return @version_3
      end
    end
  end
end
