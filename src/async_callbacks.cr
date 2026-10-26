module DiskView::AsyncCallbacks
  alias Callback = Proc(Gio::AsyncResult, Nil)

  # Keep callback boxes rooted until C invokes them. Several gi-crystal 0.26
  # async helpers omit this registration; a GC cycle can then collect captured
  # UI state while an operation is pending.
  def self.box(callback : Callback) : Pointer(Void)
    GICrystal::ClosureDataManager.register(Box.box(callback))
  end

  CALLBACK = ->(_source : Void*, result : Void*, data : Void*) {
    callback = Box(Callback).unbox(data)
    GICrystal::ClosureDataManager.deregister(data)
    callback.call(Gio::AbstractAsyncResult.new(result, :none))
  }

  def self.query_filesystem_info(file : Gio::File, attributes : String, cancellable : Gio::Cancellable, &callback : Callback)
    LibGio.g_file_query_filesystem_info_async(file, attributes, 0, cancellable, CALLBACK.pointer, box(callback))
  end
end
