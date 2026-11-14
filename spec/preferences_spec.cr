require "spec"
require "file_utils"
require "../src/preferences"

private def with_preferences_path(&)
  directory = File.tempname("disk-view-preferences", nil)
  Dir.mkdir(directory)
  begin
    yield File.join(directory, "disk-view", "size-unit")
  ensure
    FileUtils.rm_rf(directory)
  end
end

describe DiskView::Preferences do
  it "defaults to decimal units without a saved preference" do
    with_preferences_path do |path|
      DiskView::Preferences.load_size_unit(path).should eq(DiskView::SizeUnit::Decimal)
      File.exists?(path).should be_false
    end
  end

  it "restores the most recently selected unit from disk" do
    with_preferences_path do |path|
      DiskView::Preferences.save_size_unit(:binary, path).should be_true
      DiskView::Preferences.load_size_unit(path).should eq(DiskView::SizeUnit::Binary)
      DiskView::Preferences.save_size_unit(:decimal, path).should be_true
      DiskView::Preferences.load_size_unit(path).should eq(DiskView::SizeUnit::Decimal)
      Dir.children(File.dirname(path)).should eq(["size-unit"])
    end
  end

  it "falls back to GB for invalid or unreadable preferences" do
    with_preferences_path do |path|
      Dir.mkdir_p(File.dirname(path))
      {"", "unknown", "Binary\x00"}.each do |invalid|
        File.write(path, invalid)
        DiskView::Preferences.load_size_unit(path).should eq(DiskView::SizeUnit::Decimal)
      end
      File.delete(path)
      Dir.mkdir(path)
      DiskView::Preferences.load_size_unit(path).should eq(DiskView::SizeUnit::Decimal)
    end
  end

  it "preserves the existing preference if replacement fails" do
    with_preferences_path do |path|
      Dir.mkdir_p(path)
      previous = File.join(path, "previous")
      File.write(previous, "keep")
      DiskView::Preferences.save_size_unit(:binary, path).should be_false
      File.read(previous).should eq("keep")
      Dir.children(File.dirname(path)).should eq(["size-unit"])
    end
  end

  it "uses the XDG config directory, including Flatpak's per-app directory" do
    DiskView::Preferences.size_unit_path("/tmp/app-config").should eq("/tmp/app-config/disk-view/size-unit")
    fallback = (Path.home / ".config/disk-view/size-unit").to_s
    DiskView::Preferences.size_unit_path(nil).should eq(fallback)
    DiskView::Preferences.size_unit_path("").should eq(fallback)
    DiskView::Preferences.size_unit_path("relative").should eq(fallback)
  end
end
