require "spec"
require "gi-crystal/gio"
require "../src/async_callbacks"

describe DiskView::AsyncCallbacks do
  it "preserves filesystem query callbacks and captured state across garbage collection" do
    loop = GLib::MainLoop.new(nil, false)
    file = Gio::File.new_for_path(__DIR__)
    cancellable = Gio::Cancellable.new
    result = [] of UInt64
    failure = nil.as(Exception?)
    DiskView::AsyncCallbacks.query_filesystem_info(file, "filesystem::size", cancellable) do |response|
      begin
        info = file.query_filesystem_info_finish(response)
        result << info.attribute_uint64("filesystem::size")
      rescue ex
        failure = ex
      ensure
        loop.quit
      end
    end
    GC.collect
    loop.run
    failure.should be_nil
    result.size.should eq(1)
    result.first.should be > 0_u64
  end
end
