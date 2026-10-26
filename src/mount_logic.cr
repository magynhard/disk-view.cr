require "./disks"

module DiskView
  enum MountAction
    Mount
    Unmount
  end

  record MountRequest, disk : Disk, action : MountAction

  module MountLogic
    extend self

    SYSTEM_PATHS = {"/", "/boot", "/boot/efi", "/efi", "/usr", "/var", "/home", "/etc", "/run", "/dev", "/proc", "/sys"}

    def protected?(paths : Array(String)) : Bool
      paths.any? { |path| SYSTEM_PATHS.includes?(path) || path.starts_with?("/boot/") }
    end

    def eligible?(disk : Disk) : Bool
      File.dirname(disk.source) == "/dev" && disk.source != "/dev/" &&
        !disk.filesystem.empty? && disk.filesystem != "swap" && disk.measurable? &&
        !disk.metadata.encrypted? && !disk.state.locked? && !disk.state.swap? &&
        !disk.state.mapped? && disk.holders.empty? && !protected?(disk.paths)
    end

    def for_disk(disk : Disk) : Array(MountRequest)
      return [] of MountRequest unless eligible?(disk)
      [MountRequest.new(disk, disk.paths.empty? ? MountAction::Mount : MountAction::Unmount)]
    end

    # A mixed drive mounts only its remaining filesystems. Only a drive with
    # all eligible filesystems mounted switches to the collective unmount action.
    def for_drive(drive : Drive) : Array(MountRequest)
      disks = drive.filesystems.select { |disk| eligible?(disk) }
      action = disks.any?(&.paths.empty?) ? MountAction::Mount : MountAction::Unmount
      disks.select { |disk| action.mount? == disk.paths.empty? }.map { |disk| MountRequest.new(disk, action) }
    end

    def object_path(source : String) : String
      raise ArgumentError.new("Expected a local block device") unless File.dirname(source) == "/dev" && source != "/dev/"
      name = File.basename(source)
      escaped = String.build do |io|
        name.each_byte do |byte|
          if ('a'.ord <= byte <= 'z'.ord) || ('A'.ord <= byte <= 'Z'.ord) || ('0'.ord <= byte <= '9'.ord)
            io.write_byte(byte)
          else
            io << '_' << byte.to_s(16).rjust(2, '0')
          end
        end
      end
      "/org/freedesktop/UDisks2/block_devices/#{escaped}"
    end
  end
end
