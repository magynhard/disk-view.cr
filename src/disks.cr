require "set"

module DiskView
  enum DiskState
    NotMounted
    Mapped
    Swap
  end

  record Mount, device_id : String, source : String, path : String, filesystem : String
  record Disk, source : String, paths : Array(String), filesystem : String, capacity : UInt64? = nil, state : DiskState = DiskState::NotMounted, device_id : String? = nil, holders : Array(String) = [] of String
  record BlockDevice, name : String, device_id : String, capacity : UInt64, parent : String? = nil, partition_number : Int32 = 0, model : String = "", holders : Array(String) = [] of String
  record Drive, name : String, model : String, capacity : UInt64, filesystems : Array(Disk), partitioned : Bool
  record Inventory, drives : Array(Drive), other_filesystems : Array(Disk)

  module Disks
    extend self

    NETWORK_FILESYSTEMS = {"nfs", "nfs4", "cifs", "smb3", "fuse.sshfs", "fuse.rclone"}

    # Linux escapes whitespace and backslashes in mountinfo using octal sequences.
    def unescape(value : String) : String
      value.gsub(/\\([0-7]{3})/) { |match| match[1..].to_i(8).chr.to_s }
    end

    def parse_mounts(contents : String) : Array(Mount)
      contents.lines.compact_map do |line|
        halves = line.split(" - ", 2)
        next unless halves.size == 2
        fields = halves[0].split
        details = halves[1].split
        next unless fields.size >= 6 && details.size >= 3
        Mount.new(fields[2], unescape(details[1]), unescape(fields[4]), details[0])
      end
    end

    def visible?(mount : Mount) : Bool
      return false if mount.filesystem == "squashfs" || mount.source.starts_with?("/dev/loop")
      mount.path == "/" || mount.source.starts_with?("/dev/") || NETWORK_FILESYSTEMS.includes?(mount.filesystem)
    end

    def mounted_disks(mounts : Array(Mount)) : Array(Disk)
      mounts.select { |mount| visible?(mount) }
        .group_by { |mount| {mount.device_id, mount.filesystem} }
        .map do |(_device_id, filesystem), group|
          paths = group.map(&.path).uniq.sort_by { |path| {path.size, path} }
          Disk.new(group.first.source, paths, filesystem, device_id: group.first.device_id)
        end
        .sort_by { |disk| {disk.paths.includes?("/") ? 0 : 1, disk.paths.first} }
    end

    def scan : Inventory
      mounts = parse_mounts(File.read("/proc/self/mountinfo"))
      mounted = mounted_disks(mounts)
      swaps = File.read("/proc/swaps").lines.skip(1).compact_map { |line| line.split.first? }.map { |path| unescape(path) }.to_set
      hierarchy(block_devices, mounted, swaps)
    end

    def block_devices : Array(BlockDevice)
      Dir.children("/sys/class/block").sort.compact_map do |name|
        next if name.matches?(/\A(?:loop|ram|zram)\d+\z/)
        base = "/sys/class/block/#{name}"
        begin
          capacity = File.read("#{base}/size").strip.to_u64 * 512_u64
          next if capacity == 0
          partition_number = File.exists?("#{base}/partition") ? File.read("#{base}/partition").strip.to_i : 0
          parent = partition_number > 0 ? File.basename(File.dirname(File.realpath(base))) : nil
          model = begin
            File.read("#{base}/device/model").strip
          rescue File::Error
            ""
          end
          BlockDevice.new(name, File.read("#{base}/dev").strip, capacity, parent, partition_number, model, Dir.children("#{base}/holders"))
        rescue File::Error
          # Removable devices may disappear between directory listing and reading.
          nil
        end
      end
    end

    # Use sysfs relationships, not device-name suffixes: NVMe and MMC partition
    # names differ from sdX, and partitions must be sorted numerically.
    def hierarchy(blocks : Array(BlockDevice), mounted : Array(Disk), swaps = Set(String).new) : Inventory
      claimed = Set(Int32).new
      drives = blocks.select { |block| block.parent.nil? }.sort_by(&.name).map do |drive|
        partitions = blocks.select { |block| block.parent == drive.name }.sort_by(&.partition_number)
        leaves = partitions.empty? ? [drive] : partitions
        filesystems = leaves.map do |block|
          source = "/dev/#{block.name}"
          index = mounted.index { |disk| disk.device_id == block.device_id || canonical_path(disk.source) == source }
          if index
            claimed << index
            disk = mounted[index]
            Disk.new(source, disk.paths, disk.filesystem, block.capacity, device_id: block.device_id)
          else
            state = if !block.holders.empty?
                      DiskState::Mapped
                    elsif swaps.includes?(source)
                      DiskState::Swap
                    else
                      DiskState::NotMounted
                    end
            Disk.new(source, [] of String, "", block.capacity, state, block.device_id, block.holders)
          end
        end
        Drive.new(drive.name, drive.model, drive.capacity, filesystems, !partitions.empty?)
      end
      others = mounted.each_with_index.reject { |(_, index)| claimed.includes?(index) }.map(&.[0]).to_a
      Inventory.new(drives, others)
    end

    private def canonical_path(path : String) : String
      File.realpath(path)
    rescue File::Error
      path
    end
  end

  def self.format_bytes(bytes : UInt64) : String
    units = {"B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"}
    value = bytes.to_f64
    unit = 0
    while value >= 1024 && unit < units.size - 1
      value /= 1024
      unit += 1
    end
    unit == 0 ? "#{bytes} B" : "#{value.format(decimal_places: 1)} #{units[unit]}"
  end

  record Usage, total : UInt64, free : UInt64, available : UInt64 do
    def used : UInt64
      total - free.clamp(0_u64, total)
    end

    def reserved : UInt64
      free.clamp(0_u64, total) - available.clamp(0_u64, free.clamp(0_u64, total))
    end

    def fraction : Float64
      total == 0 ? 0.0 : used.to_f64 / total
    end
  end

  record Summary, capacity : UInt64, used : UInt64, available : UInt64, reserved : UInt64, known_count : Int32, filesystem_count : Int32 do
    def self.for_drive(drive : Drive, usages : Array(Usage?)) : self
      # A pooled filesystem may report the capacity of several devices. Do not
      # attribute its entire usage to one smaller physical partition.
      known = usages.each_with_index.compact_map do |usage, index|
        next unless usage
        limit = drive.filesystems[index].capacity || drive.capacity
        usage if usage.total <= limit
      end.to_a
      new(drive.capacity, known.sum(0_u64, &.used), known.sum(0_u64) { |usage| usage.available.clamp(0_u64, usage.total) },
        known.sum(0_u64, &.reserved), known.size, drive.filesystems.size)
    end

    def complete? : Bool
      known_count == filesystem_count
    end

    def fraction : Float64
      capacity == 0 ? 0.0 : (used.to_f64 / capacity).clamp(0.0, 1.0)
    end
  end
end
