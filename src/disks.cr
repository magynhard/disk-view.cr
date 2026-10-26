require "set"
require "./device_metadata"
require "./platform_paths"

module DiskView
  enum DiskState
    NotMounted
    Mapped
    Swap
    Locked
  end

  record Mount, device_id : String, source : String, path : String, filesystem : String
  record Disk, source : String, paths : Array(String), filesystem : String, capacity : UInt64? = nil, state : DiskState = DiskState::NotMounted, device_id : String? = nil, holders : Array(String) = [] of String, metadata : BlockMetadata = BlockMetadata.new do
    def measurable? : Bool
      metadata.role != PartitionRole::MicrosoftReserved || !filesystem.empty?
    end
  end

  record BlockDevice, name : String, device_id : String, capacity : UInt64, parent : String? = nil, partition_number : Int32 = 0, model : String = "", holders : Array(String) = [] of String, metadata : BlockMetadata = BlockMetadata.new, rotational : Bool? = nil
  record Drive, name : String, model : String, capacity : UInt64, filesystems : Array(Disk), partitioned : Bool, rotational : Bool? = nil
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
      mounts = parse_mounts(File.read(PlatformPaths.mountinfo))
      mounted = mounted_disks(mounts)
      swaps = File.read(PlatformPaths.host_path("/proc/swaps")).lines.skip(1).compact_map { |line| line.split.first? }.map { |path| unescape(path) }.to_set
      hierarchy(block_devices, mounted, swaps)
    end

    def block_devices : Array(BlockDevice)
      block_path = PlatformPaths.host_path("/sys/class/block")
      names = Dir.children(block_path).sort.reject { |name| name.matches?(/\A(?:loop|ram|zram)\d+\z/) }
      metadata = UdevMetadata.read(names)
      names.compact_map do |name|
        base = "#{block_path}/#{name}"
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
          details = metadata[name]? || BlockMetadata.new
          rotational = if parent.nil? && details.device_type != "cd" && (details.device_type == "disk" || File.exists?("#{base}/device"))
                         begin
                           case File.read("#{base}/queue/rotational").strip
                           when "0" then false
                           when "1" then true
                           end
                         rescue File::Error
                           nil
                         end
                       end
          BlockDevice.new(name, File.read("#{base}/dev").strip, capacity, parent, partition_number, model, Dir.children("#{base}/holders"), details, rotational)
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
            filesystem = block.metadata.filesystem.empty? ? disk.filesystem : block.metadata.filesystem
            Disk.new(source, disk.paths, filesystem, block.capacity, device_id: block.device_id, metadata: block.metadata)
          else
            state = if !block.holders.empty?
                      DiskState::Mapped
                    elsif swaps.includes?(source)
                      DiskState::Swap
                    elsif block.metadata.encrypted?
                      DiskState::Locked
                    else
                      DiskState::NotMounted
                    end
            Disk.new(source, [] of String, block.metadata.filesystem, block.capacity, state, block.device_id, block.holders, block.metadata)
          end
        end
        Drive.new(drive.name, drive.model, drive.capacity, filesystems, !partitions.empty?, drive.rotational)
      end
      others = mounted.each_with_index.reject { |(_, index)| claimed.includes?(index) }.map(&.[0]).to_a
      Inventory.new(drives, others)
    end

    def filesystem_name(filesystem : String) : String
      case filesystem.downcase
      when "ntfs", "ntfs3"             then "NTFS"
      when "exfat"                     then "exFAT"
      when "vfat", "fat", "msdos"      then "FAT"
      when "bitlocker", "crypto_bitlk" then "BitLocker"
      when "crypto_luks"               then "LUKS"
      else                                  filesystem
      end
    end

    private def canonical_path(path : String) : String
      return path unless path.starts_with?("/dev/")
      resolved = File.realpath(PlatformPaths.host_path(path))
      if PlatformPaths.sandboxed? && resolved.starts_with?(PlatformPaths::HOST_ROOT + "/")
        resolved[PlatformPaths::HOST_ROOT.bytesize..]
      else
        resolved
      end
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
        next unless drive.filesystems[index].measurable?
        limit = drive.filesystems[index].capacity || drive.capacity
        usage if usage.total <= limit
      end.to_a
      new(drive.capacity, known.sum(0_u64, &.used), known.sum(0_u64) { |usage| usage.available.clamp(0_u64, usage.total) },
        known.sum(0_u64, &.reserved), known.size, drive.filesystems.count(&.measurable?))
    end

    def complete? : Bool
      known_count == filesystem_count
    end

    def fraction : Float64
      capacity == 0 ? 0.0 : (used.to_f64 / capacity).clamp(0.0, 1.0)
    end
  end
end
