require "spec"
require "../src/disks"

describe DiskView::Disks do
  it "decodes escaped mount paths without decoding a literal backslash twice" do
    DiskView::Disks.unescape("/media/My\\040Disk\\134040").should eq("/media/My Disk\\040")
  end

  it "parses mountinfo with optional fields and escaped names" do
    mounts = DiskView::Disks.parse_mounts("30 1 8:2 / /media/My\\040Disk rw shared:1 - ext4 /dev/sda2 rw\ninvalid\n")
    mounts.should eq([DiskView::Mount.new("8:2", "/dev/sda2", "/media/My Disk", "ext4")])
  end

  it "groups bind mounts and subvolumes and hides virtual and snap filesystems" do
    mounts = DiskView::Disks.parse_mounts(<<-MOUNTS)
      1 0 8:2 / / rw - ext4 /dev/sda2 rw
      2 1 8:2 /home /home rw - ext4 /dev/sda2 rw
      3 1 0:1 / /proc rw - proc proc rw
      4 1 7:0 / /snap/example ro - squashfs /dev/loop0 ro
      5 1 0:3 / /media/share rw - cifs //server/share rw
      MOUNTS
    disks = DiskView::Disks.mounted_disks(mounts)
    disks.size.should eq(2)
    disks.first.paths.should eq(["/", "/home"])
    disks.last.source.should eq("//server/share")
  end

  it "does not duplicate a filesystem mounted through different device aliases" do
    mounts = [
      DiskView::Mount.new("8:2", "/dev/sda2", "/", "ext4"),
      DiskView::Mount.new("8:2", "/dev/disk/by-uuid/example", "/mnt/root", "ext4"),
    ]
    disks = DiskView::Disks.mounted_disks(mounts)
    disks.size.should eq(1)
    disks.first.paths.should eq(["/", "/mnt/root"])
  end

  it "groups partitions by sysfs parent and sorts partition numbers numerically" do
    blocks = [
      DiskView::BlockDevice.new("sda", "8:0", 1000_u64),
      DiskView::BlockDevice.new("sda10", "8:10", 200_u64, "sda", 10),
      DiskView::BlockDevice.new("sda2", "8:2", 700_u64, "sda", 2),
      DiskView::BlockDevice.new("nvme0n1", "259:0", 2000_u64),
      DiskView::BlockDevice.new("nvme0n1p1", "259:1", 1900_u64, "nvme0n1", 1),
    ]
    mounted = [DiskView::Disk.new("/dev/disk/by-uuid/example", ["/"], "ext4", device_id: "8:2")]
    inventory = DiskView::Disks.hierarchy(blocks, mounted)
    inventory.drives.map(&.name).should eq(["nvme0n1", "sda"])
    sda = inventory.drives.last
    sda.capacity.should eq(1000)
    sda.partitioned.should be_true
    sda.filesystems.map(&.source).should eq(["/dev/sda2", "/dev/sda10"])
    sda.filesystems.first.paths.should eq(["/"])
    sda.filesystems.last.state.should eq(DiskView::DiskState::NotMounted)
    inventory.other_filesystems.should be_empty
  end

  it "keeps whole-disk filesystems and network mounts without duplicating the disk" do
    blocks = [DiskView::BlockDevice.new("sdb", "8:16", 1000_u64)]
    mounted = [
      DiskView::Disk.new("/dev/sdb", ["/data"], "ext4", device_id: "8:16"),
      DiskView::Disk.new("server:/share", ["/network"], "nfs", device_id: "0:40"),
    ]
    inventory = DiskView::Disks.hierarchy(blocks, mounted)
    inventory.drives.size.should eq(1)
    inventory.drives.first.partitioned.should be_false
    inventory.drives.first.filesystems.size.should eq(1)
    inventory.drives.first.filesystems.first.paths.should eq(["/data"])
    inventory.other_filesystems.map(&.source).should eq(["server:/share"])
  end

  it "distinguishes mapped partitions and active swap from unmounted filesystems" do
    blocks = [
      DiskView::BlockDevice.new("sda", "8:0", 1000_u64),
      DiskView::BlockDevice.new("sda1", "8:1", 700_u64, "sda", 1, holders: ["dm-0"]),
      DiskView::BlockDevice.new("sda2", "8:2", 200_u64, "sda", 2),
    ]
    inventory = DiskView::Disks.hierarchy(blocks, [] of DiskView::Disk, Set{"/dev/sda2"})
    inventory.drives.first.filesystems.map(&.state).should eq([DiskView::DiskState::Mapped, DiskView::DiskState::Swap])
    inventory.drives.first.filesystems.first.holders.should eq(["dm-0"])
  end
end

describe DiskView::Summary do
  it "sums occupied space but uses physical capacity for the drive percentage" do
    drive = DiskView::Drive.new("sda", "", 1000_u64, [
      DiskView::Disk.new("/dev/sda1", ["/"], "ext4", 500_u64),
      DiskView::Disk.new("/dev/sda2", ["/home"], "ext4", 400_u64),
    ], true)
    usages = [DiskView::Usage.new(500_u64, 200_u64, 180_u64), DiskView::Usage.new(400_u64, 200_u64, 190_u64)] of DiskView::Usage?
    summary = DiskView::Summary.for_drive(drive, usages)
    summary.used.should eq(500)
    summary.available.should eq(370)
    summary.reserved.should eq(30)
    summary.fraction.should eq(0.5)
    summary.complete?.should be_true
  end

  it "reports incomplete usage instead of treating an unreadable partition as free" do
    drive = DiskView::Drive.new("sda", "", 1000_u64, [
      DiskView::Disk.new("/dev/sda1", ["/"], "ext4", 500_u64),
      DiskView::Disk.new("/dev/sda2", [] of String, "", 400_u64),
    ], true)
    summary = DiskView::Summary.for_drive(drive, [DiskView::Usage.new(500_u64, 200_u64, 180_u64), nil])
    summary.complete?.should be_false
    summary.known_count.should eq(1)
    summary.filesystem_count.should eq(2)
    summary.used.should eq(300)
    summary.available.should eq(180)
  end

  it "does not attribute an entire multi-device pool to a smaller partition" do
    drive = DiskView::Drive.new("sda", "", 1000_u64, [DiskView::Disk.new("/dev/sda1", ["/"], "btrfs", 900_u64)], true)
    summary = DiskView::Summary.for_drive(drive, [DiskView::Usage.new(2000_u64, 500_u64, 500_u64)] of DiskView::Usage?)
    summary.known_count.should eq(0)
    summary.used.should eq(0)
    summary.complete?.should be_false
  end
end

describe DiskView::Usage do
  it "distinguishes occupied, available and reserved space" do
    usage = DiskView::Usage.new(1000_u64, 400_u64, 350_u64)
    usage.used.should eq(600)
    usage.reserved.should eq(50)
    usage.fraction.should eq(0.6)
  end

  it "handles empty media and inconsistent filesystem counters" do
    DiskView::Usage.new(0_u64, 0_u64, 0_u64).fraction.should eq(0.0)
    usage = DiskView::Usage.new(100_u64, 200_u64, 300_u64)
    usage.used.should eq(0)
    usage.reserved.should eq(0)
  end
end

describe ".format_bytes" do
  it "uses binary units with readable precision" do
    DiskView.format_bytes(0_u64).should eq("0 B")
    DiskView.format_bytes(1536_u64).should eq("1.5 KiB")
    DiskView.format_bytes(1_099_511_627_776_u64).should eq("1.0 TiB")
  end
end
