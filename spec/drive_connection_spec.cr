require "spec"
require "../src/disks"

describe "Drive connections" do
  it "shows USB rather than HDD for a stick reporting rotational media" do
    metadata = DiskView::BlockMetadata.from_properties({"ID_BUS" => "usb", "ID_TYPE" => "disk"})
    blocks = [DiskView::BlockDevice.new("sdd", "8:48", 1000_u64, metadata: metadata, rotational: true)]
    drive = DiskView::Disks.hierarchy(blocks, [] of DiskView::Disk).drives.first
    drive.connection.should eq("USB")
    drive.media_description.should eq("USB")
  end

  it "identifies the USB connection rather than the SATA disk behind a bridge" do
    metadata = DiskView::BlockMetadata.from_properties({"ID_BUS" => "usb", "ID_ATA_SATA" => "1"})
    metadata.connection.should eq("USB")
    [true, false, nil].each do |rotational|
      drive = DiskView::Drive.new("sdd", "", 1000_u64, [] of DiskView::Disk, false, rotational, metadata.connection)
      drive.media_description.should eq("USB")
    end
  end

  it "distinguishes SATA from unspecified ATA and SCSI devices" do
    DiskView::BlockMetadata.from_properties({"ID_BUS" => "ata", "ID_ATA_SATA" => "1"}).connection.should eq("SATA")
    DiskView::BlockMetadata.from_properties({"ID_BUS" => "sata"}).connection.should eq("SATA")
    DiskView::BlockMetadata.from_properties({"ID_BUS" => "ata"}).connection.should be_empty
    DiskView::BlockMetadata.from_properties({"ID_BUS" => "scsi"}).connection.should be_empty
    DiskView::BlockMetadata.new.connection.should be_empty
  end

  it "combines the connection and media type for SATA drives" do
    metadata = DiskView::BlockMetadata.from_properties({"ID_BUS" => "ata", "ID_ATA_SATA" => "1"})
    blocks = [
      DiskView::BlockDevice.new("sda", "8:0", 1000_u64, metadata: metadata, rotational: false),
      DiskView::BlockDevice.new("sdb", "8:16", 2000_u64, metadata: metadata, rotational: true),
    ]
    DiskView::Disks.hierarchy(blocks, [] of DiskView::Disk).drives.map(&.media_description).should eq(["SSD · SATA", "HDD · SATA"])
  end

  it "uses the whole drive connection when grouping partitions" do
    usb = DiskView::BlockMetadata.from_properties({"ID_BUS" => "usb"})
    blocks = [
      DiskView::BlockDevice.new("sdd", "8:48", 1000_u64, metadata: usb, rotational: true),
      DiskView::BlockDevice.new("sdd1", "8:49", 900_u64, "sdd", 1),
    ]
    drive = DiskView::Disks.hierarchy(blocks, [] of DiskView::Disk).drives.first
    drive.media_description.should eq("USB")
    drive.filesystems.map(&.source).should eq(["/dev/sdd1"])
  end

  it "recognizes NVMe and card reader buses from udev" do
    DiskView::BlockMetadata.from_properties({"ID_BUS" => "nvme"}).connection.should eq("NVMe")
    DiskView::BlockMetadata.from_properties({"ID_BUS" => "mmc"}).connection.should eq("SD/MMC")
  end

  it "recognizes native NVMe and MMC devices without cached udev properties" do
    blocks = [
      DiskView::BlockDevice.new("nvme0n1", "259:0", 2000_u64, rotational: false),
      DiskView::BlockDevice.new("nvme2c1n3", "259:1", 2000_u64, rotational: false),
      DiskView::BlockDevice.new("mmcblk0", "179:0", 1000_u64, rotational: false),
    ]
    drives = DiskView::Disks.hierarchy(blocks, [] of DiskView::Disk).drives
    drives.map(&.media_description).should eq(["SD/MMC", "SSD · NVMe", "SSD · NVMe"])
  end

  it "omits missing information without assuming sdX devices use SATA" do
    blocks = [DiskView::BlockDevice.new("sda", "8:0", 1000_u64)]
    drive = DiskView::Disks.hierarchy(blocks, [] of DiskView::Disk).drives.first
    drive.connection.should be_empty
    drive.media_description.should be_empty
    DiskView::Drive.new("sda", "", 1000_u64, [] of DiskView::Disk, false, connection: "SATA").media_description.should eq("SATA")
    DiskView::Drive.new("sda", "", 1000_u64, [] of DiskView::Disk, false, false).media_description.should eq("SSD")
  end
end
