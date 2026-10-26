require "spec"
require "../src/disks"

describe DiskView::BlockMetadata do
  it "decodes UTF-8 labels and literal backslashes exactly once" do
    metadata = DiskView::BlockMetadata.from_properties({
      "ID_FS_TYPE"         => "ntfs",
      "ID_FS_LABEL"        => "My_Disk",
      "ID_FS_LABEL_ENC"    => "My\\x20Disk\\x20\\xc3\\xa4\\x5cx20",
      "ID_PART_ENTRY_NAME" => "Basic\\x20data\\x20partition",
    })
    metadata.filesystem.should eq("ntfs")
    metadata.label.should eq("My Disk ä\\x20")
    metadata.partition_name.should eq("Basic data partition")
  end

  it "handles missing properties, raw names and malformed byte sequences" do
    metadata = DiskView::BlockMetadata.from_properties({"ID_FS_LABEL" => "DATA", "PARTNAME" => "Raw name"})
    metadata.label.should eq("DATA")
    metadata.partition_name.should eq("Raw name")
    metadata.role.should eq(DiskView::PartitionRole::Unknown)
    DiskView::BlockMetadata.decode("broken\\xZZ").should eq("broken\\xZZ")
    DiskView::BlockMetadata.decode("broken\\x+4").should eq("broken\\x+4")
    DiskView::BlockMetadata.decode("line\\x0aname").should eq("line name")
    DiskView::BlockMetadata.from_properties({} of String => String).should eq(DiskView::BlockMetadata.new)
  end

  it "identifies GPT and MBR Windows recovery and EFI partition types" do
    DiskView::BlockMetadata.new(partition_type: "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC").role.should eq(DiskView::PartitionRole::WindowsRecovery)
    DiskView::BlockMetadata.new(partition_type: "0x27").role.should eq(DiskView::PartitionRole::WindowsRecovery)
    DiskView::BlockMetadata.new(partition_type: "0x07").role.should eq(DiskView::PartitionRole::MicrosoftData)
    DiskView::BlockMetadata.new(partition_type: "c12a7328-f81f-11d2-ba4b-00a0c93ec93b").role.should eq(DiskView::PartitionRole::EfiSystem)
    DiskView::BlockMetadata.new(partition_type: "0xef").role.should eq(DiskView::PartitionRole::EfiSystem)
  end
end

describe "Windows storage discovery" do
  it "preserves NTFS identities and partition roles without any mount or device access" do
    reserved = DiskView::BlockMetadata.new(partition_name: "Microsoft reserved partition", partition_type: "e3c9e316-0b5c-4db8-817d-f92df00215ae")
    data = DiskView::BlockMetadata.new("ntfs", "Windows", partition_type: "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7")
    recovery = DiskView::BlockMetadata.new("ntfs", partition_type: "de94bba4-06d1-4d40-a16a-bfd50179d6ac")
    blocks = [
      DiskView::BlockDevice.new("sda", "8:0", 1000_u64, rotational: false),
      DiskView::BlockDevice.new("sda1", "8:1", 16_u64, "sda", 1, metadata: reserved),
      DiskView::BlockDevice.new("sda2", "8:2", 900_u64, "sda", 2, metadata: data),
      DiskView::BlockDevice.new("sda3", "8:3", 80_u64, "sda", 3, metadata: recovery),
    ]
    drive = DiskView::Disks.hierarchy(blocks, [] of DiskView::Disk).drives.first
    drive.rotational.should be_false
    drive.filesystems.map(&.filesystem).should eq(["", "ntfs", "ntfs"])
    drive.filesystems[1].metadata.label.should eq("Windows")
    drive.filesystems.map(&.measurable?).should eq([false, true, true])
    drive.filesystems.map(&.metadata.role).should eq([DiskView::PartitionRole::MicrosoftReserved, DiskView::PartitionRole::MicrosoftData, DiskView::PartitionRole::WindowsRecovery])
    summary = DiskView::Summary.for_drive(drive, Array(DiskView::Usage?).new(3, nil))
    summary.filesystem_count.should eq(2)
    summary.known_count.should eq(0)
    summary.complete?.should be_false
  end

  it "uses cached NTFS metadata when Linux mounts NTFS through fuseblk" do
    metadata = DiskView::BlockMetadata.new("ntfs", "Windows")
    blocks = [DiskView::BlockDevice.new("sda", "8:0", 1000_u64, metadata: metadata)]
    mounted = [DiskView::Disk.new("/dev/sda", ["/media/Windows"], "fuseblk", device_id: "8:0")]
    disk = DiskView::Disks.hierarchy(blocks, mounted).drives.first.filesystems.first
    disk.filesystem.should eq("ntfs")
    disk.metadata.label.should eq("Windows")
    disk.paths.should eq(["/media/Windows"])
    DiskView::Disks.filesystem_name(disk.filesystem).should eq("NTFS")
    DiskView::Disks.filesystem_name("ntfs3").should eq("NTFS")
    DiskView::Disks.filesystem_name("exfat").should eq("exFAT")
  end

  it "falls back to mounted filesystem data when udev has no identification data" do
    blocks = [DiskView::BlockDevice.new("sda", "8:0", 1000_u64)]
    mounted = [DiskView::Disk.new("/dev/sda", ["/media/Windows"], "ntfs3", device_id: "8:0")]
    DiskView::Disks.hierarchy(blocks, mounted).drives.first.filesystems.first.filesystem.should eq("ntfs3")
  end

  it "distinguishes locked BitLocker from an unlocked mapped device" do
    metadata = DiskView::BlockMetadata.new("BitLocker")
    locked = [DiskView::BlockDevice.new("sda", "8:0", 1000_u64, metadata: metadata)]
    unlocked = [DiskView::BlockDevice.new("sda", "8:0", 1000_u64, metadata: metadata, holders: ["dm-0"])]
    DiskView::Disks.hierarchy(locked, [] of DiskView::Disk).drives.first.filesystems.first.state.should eq(DiskView::DiskState::Locked)
    DiskView::Disks.hierarchy(unlocked, [] of DiskView::Disk).drives.first.filesystems.first.state.should eq(DiskView::DiskState::Mapped)
  end

  it "does not count a filesystem-less MSR as an unknown filesystem in totals" do
    reserved = DiskView::Disk.new("/dev/sda1", [] of String, "", 16_u64, metadata: DiskView::BlockMetadata.new(partition_type: "e3c9e316-0b5c-4db8-817d-f92df00215ae"))
    data = DiskView::Disk.new("/dev/sda2", ["/media/Windows"], "ntfs", 900_u64)
    drive = DiskView::Drive.new("sda", "", 1000_u64, [reserved, data], true)
    summary = DiskView::Summary.for_drive(drive, [nil, DiskView::Usage.new(900_u64, 300_u64, 300_u64)])
    summary.complete?.should be_true
    summary.filesystem_count.should eq(1)
    summary.used.should eq(600)
    summary.fraction.should eq(0.6)
  end
end
