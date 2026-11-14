require "./disks"

module DiskView::Preferences
  def self.size_unit_path(config_home = ENV["XDG_CONFIG_HOME"]?) : String
    root = config_home && Path[config_home].absolute? ? config_home : (Path.home / ".config").to_s
    File.join(root, "disk-view", "size-unit")
  end

  def self.load_size_unit(path : String = size_unit_path) : SizeUnit
    File.read(path).strip == "GiB" ? SizeUnit::Binary : SizeUnit::Decimal
  rescue File::Error | IO::Error
    SizeUnit::Decimal
  end

  def self.save_size_unit(size_unit : SizeUnit, path : String = size_unit_path) : Bool
    directory = File.dirname(path)
    Dir.mkdir_p(directory)
    temporary = File.tempfile("size-unit", dir: directory)
    begin
      temporary.puts(size_unit.binary? ? "GiB" : "GB")
      temporary.close
      File.rename(temporary.path, path)
    ensure
      temporary.close
      File.delete?(temporary.path)
    end
    true
  rescue ex : File::Error | IO::Error
    STDERR.puts "Could not save size units: #{ex.message}"
    false
  end
end
