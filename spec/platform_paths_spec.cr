require "spec"
require "../src/platform_paths"

describe DiskView::PlatformPaths do
  it "keeps native mount discovery in the current process namespace" do
    DiskView::PlatformPaths.mountinfo(false).should eq("/proc/self/mountinfo")
    DiskView::PlatformPaths.host_path("/extendo", false).should eq("/extendo")
  end

  it "reads host mount data rather than Flatpak's runtime mounts" do
    DiskView::PlatformPaths.mountinfo(true).should eq("/run/host/root/proc/1/mountinfo")
    DiskView::PlatformPaths.host_path("/", true).should eq("/run/host/root/")
    DiskView::PlatformPaths.host_path("/sys/class/block", true).should eq("/run/host/root/sys/class/block")
    DiskView::PlatformPaths.host_path("/media/My Disk", true).should eq("/run/host/root/media/My Disk")
  end

  it "rejects paths that could escape the host-root mapping" do
    expect_raises(ArgumentError) { DiskView::PlatformPaths.host_path("relative", true) }
    expect_raises(ArgumentError) { DiskView::PlatformPaths.host_path("/../etc", true) }
  end
end
