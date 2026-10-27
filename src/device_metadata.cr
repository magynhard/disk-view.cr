module DiskView
  enum PartitionRole
    Unknown
    MicrosoftReserved
    MicrosoftData
    WindowsRecovery
    EfiSystem
  end

  record BlockMetadata,
    filesystem : String = "",
    label : String = "",
    partition_name : String = "",
    partition_type : String = "",
    device_type : String = "",
    connection : String = "" do
    def self.from_properties(properties : Hash(String, String)) : self
      encoded_label = properties["ID_FS_LABEL_ENC"]? || ""
      encoded_name = properties["ID_PART_ENTRY_NAME"]? || ""
      connection = case properties["ID_BUS"]?
                   when "usb"  then "USB"
                   when "nvme" then "NVMe"
                   when "mmc"  then "SD/MMC"
                   when "sata" then "SATA"
                   when "ata"
                     properties["ID_ATA_SATA"]? == "1" ? "SATA" : ""
                   else
                     ""
                   end
      new(
        properties["ID_FS_TYPE"]? || "",
        encoded_label.empty? ? (properties["ID_FS_LABEL"]? || "") : decode(encoded_label),
        encoded_name.empty? ? (properties["PARTNAME"]? || "") : decode(encoded_name),
        properties["ID_PART_ENTRY_TYPE"]? || "",
        properties["ID_TYPE"]? || "",
        connection
      )
    end

    # udev encodes bytes, not Unicode codepoints. Decode only once, then
    # interpret the complete byte sequence as UTF-8 (including non-ASCII labels).
    def self.decode(value : String) : String
      decoded = String.build do |io|
        bytes = value.to_slice
        index = 0
        while index < bytes.size
          if index + 3 < bytes.size && bytes[index] == '\\'.ord && bytes[index + 1] == 'x'.ord
            hex = String.new(bytes[index + 2, 2])
            if hex.matches?(/\A[0-9a-fA-F]{2}\z/)
              io.write_byte(hex.to_u8(16))
              index += 4
              next
            end
          end
          io.write_byte(bytes[index])
          index += 1
        end
      end
      decoded.scrub.gsub(/[\x00-\x1f\x7f]/, " ")
    end

    def role : PartitionRole
      case partition_type.downcase
      when "e3c9e316-0b5c-4db8-817d-f92df00215ae"
        PartitionRole::MicrosoftReserved
      when "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7", "0x7", "0x07"
        PartitionRole::MicrosoftData
      when "de94bba4-06d1-4d40-a16a-bfd50179d6ac", "0x27"
        PartitionRole::WindowsRecovery
      when "c12a7328-f81f-11d2-ba4b-00a0c93ec93b", "0xef"
        PartitionRole::EfiSystem
      else
        PartitionRole::Unknown
      end
    end

    def encrypted? : Bool
      {"bitlocker", "crypto_bitlk", "crypto_luks"}.includes?(filesystem.downcase)
    end
  end

  @[Link("udev", pkg_config: "libudev")]
  lib LibUdev
    fun udev_new : Void*
    fun udev_unref(context : Void*) : Void*
    fun udev_device_new_from_subsystem_sysname(context : Void*, subsystem : UInt8*, name : UInt8*) : Void*
    fun udev_device_get_property_value(device : Void*, key : UInt8*) : UInt8*
    fun udev_device_unref(device : Void*) : Void*
  end

  module UdevMetadata
    extend self

    PROPERTIES = {"ID_FS_TYPE", "ID_FS_LABEL_ENC", "ID_FS_LABEL", "ID_PART_ENTRY_NAME", "PARTNAME", "ID_PART_ENTRY_TYPE", "ID_TYPE", "ID_BUS", "ID_ATA_SATA"}

    # Read udev's cached identification data, without probing device contents,
    # mounting filesystems, spawning commands or requiring elevated privileges.
    def read(names : Array(String)) : Hash(String, BlockMetadata)
      result = {} of String => BlockMetadata
      context = LibUdev.udev_new
      return result if context.null?
      begin
        names.each do |name|
          device = LibUdev.udev_device_new_from_subsystem_sysname(context, "block", name)
          next if device.null?
          begin
            properties = {} of String => String
            PROPERTIES.each do |key|
              value = LibUdev.udev_device_get_property_value(device, key)
              properties[key] = String.new(value).scrub unless value.null?
            end
            result[name] = BlockMetadata.from_properties(properties)
          ensure
            LibUdev.udev_device_unref(device)
          end
        end
      ensure
        LibUdev.udev_unref(context)
      end
      result
    end
  end
end
