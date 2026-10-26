require "spec"
require "../src/mount_logic"

private def filesystem(source = "/dev/sda1", paths = [] of String, type = "ntfs")
  DiskView::Disk.new(source, paths, type, 1000_u64)
end

describe DiskView::MountLogic do
  it "toggles individual filesystems according to their current mount state" do
    DiskView::MountLogic.for_disk(filesystem).first.action.should eq(DiskView::MountAction::Mount)
    DiskView::MountLogic.for_disk(filesystem(paths: ["/media/Windows"])).first.action.should eq(DiskView::MountAction::Unmount)
  end

  it "mounts only the remaining partitions of a mixed drive" do
    mounted = filesystem("/dev/sda1", ["/media/data"])
    unmounted = filesystem("/dev/sda2")
    drive = DiskView::Drive.new("sda", "", 2000_u64, [mounted, unmounted], true)
    plan = DiskView::MountLogic.for_drive(drive)
    plan.map(&.disk.source).should eq(["/dev/sda2"])
    plan.map(&.action).should eq([DiskView::MountAction::Mount])
  end

  it "unmounts all eligible partitions only when they are all mounted" do
    disks = [filesystem("/dev/sda1", ["/media/one"]), filesystem("/dev/sda2", ["/media/two"])]
    drive = DiskView::Drive.new("sda", "", 2000_u64, disks, true)
    plan = DiskView::MountLogic.for_drive(drive)
    plan.map(&.disk.source).should eq(["/dev/sda1", "/dev/sda2"])
    plan.all?(&.action.unmount?).should be_true
  end

  it "excludes reserved, encrypted, swap, mapped and unknown filesystems" do
    disks = [
      DiskView::Disk.new("/dev/sda1", [] of String, "", metadata: DiskView::BlockMetadata.new(partition_type: "e3c9e316-0b5c-4db8-817d-f92df00215ae")),
      DiskView::Disk.new("/dev/sda2", [] of String, "BitLocker", metadata: DiskView::BlockMetadata.new("BitLocker")),
      DiskView::Disk.new("/dev/sda3", [] of String, "swap", state: DiskView::DiskState::Swap),
      DiskView::Disk.new("/dev/sda4", [] of String, "ext4", state: DiskView::DiskState::Mapped, holders: ["dm-0"]),
      filesystem("/dev/sda5", type: ""),
      filesystem("server:/share", ["/network"], "nfs"),
    ]
    disks.each { |disk| DiskView::MountLogic.for_disk(disk).should be_empty }
  end

  it "protects system mount points even when another bind mount is also present" do
    {"/", "/boot", "/boot/efi", "/usr", "/var", "/home", "/run"}.each do |path|
      DiskView::MountLogic.for_disk(filesystem(paths: ["/media/bind", path])).should be_empty
    end
    DiskView::MountLogic.for_disk(filesystem(paths: ["/home/user/external"])).should_not be_empty
    DiskView::MountLogic.for_disk(filesystem(paths: ["/extendo"])).should_not be_empty
  end

  it "does not let protected system partitions participate in a collective action" do
    system = filesystem("/dev/sdb2", ["/"])
    data = filesystem("/dev/sdb3", ["/media/data"])
    drive = DiskView::Drive.new("sdb", "", 2000_u64, [system, data], true)
    plan = DiskView::MountLogic.for_drive(drive)
    plan.size.should eq(1)
    plan.first.disk.source.should eq("/dev/sdb3")
    plan.first.action.should eq(DiskView::MountAction::Unmount)
  end

  it "encodes device names for UDisks object paths without a shell" do
    DiskView::MountLogic.object_path("/dev/sda1").should eq("/org/freedesktop/UDisks2/block_devices/sda1")
    DiskView::MountLogic.object_path("/dev/dm-0").should eq("/org/freedesktop/UDisks2/block_devices/dm_2d0")
    DiskView::MountLogic.object_path("/dev/test_name").should eq("/org/freedesktop/UDisks2/block_devices/test_5fname")
    expect_raises(ArgumentError) { DiskView::MountLogic.object_path("/dev/mapper/name") }
    expect_raises(ArgumentError) { DiskView::MountLogic.object_path("/tmp/sda1") }
  end
end
