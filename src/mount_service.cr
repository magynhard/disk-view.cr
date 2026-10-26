require "./mount_logic"
require "./i18n"
require "./async_callbacks"

module DiskView
  # bus_get also generates an invalid source-object wrapper for its nullable
  # source in gi-crystal 0.26, so use the C entry points with retained callbacks.
  private module MountDBus
    alias Callback = AsyncCallbacks::Callback

    def self.connect(cancellable : Gio::Cancellable, &callback : Callback)
      LibGio.g_bus_get(Gio::BusType::System, cancellable, AsyncCallbacks::CALLBACK.pointer, AsyncCallbacks.box(callback))
    end

    def self.finish_connect(result : Gio::AsyncResult) : Gio::DBusConnection
      error = Pointer(LibGLib::Error).null
      pointer = LibGio.g_bus_get_finish(result, pointerof(error))
      Gio.raise_gerror(error) unless error.null?
      Gio::DBusConnection.new(pointer, :full)
    end

    def self.call(connection : Gio::DBusConnection, path : String, interface : String, method : String, parameters : GLib::Variant, cancellable : Gio::Cancellable, &callback : Callback)
      LibGio.g_dbus_connection_call(connection, "org.freedesktop.UDisks2", path, interface, method, parameters, nil,
        Gio::DBusCallFlags::AllowInteractiveAuthorization, 120_000, cancellable, AsyncCallbacks::CALLBACK.pointer, AsyncCallbacks.box(callback))
    end
  end

  class MountService
    include I18n

    private def error_text(error : Exception) : String
      (error.message || translate("UDisks2 is unavailable.")).sub(/\AGDBus\.Error:[^:]+:\s*/, "")
    end

    private def child(value : GLib::Variant, index : Int32) : GLib::Variant
      GLib::Variant.new(LibGLib.g_variant_get_child_value(value, index.to_u64), :full)
    end

    private def property(value : GLib::Variant, key : String) : GLib::Variant?
      pointer = LibGLib.g_variant_lookup_value(value, key, nil)
      GLib::Variant.new(pointer, :full) unless pointer.null?
    end

    private def mount_points(properties : GLib::Variant) : Array(String)
      points = property(properties, "MountPoints")
      raise translate("The filesystem is no longer available.") unless points
      Array(String).new(LibGLib.g_variant_n_children(points).to_i) do |index|
        bytes = child(points, index)
        String.build do |io|
          LibGLib.g_variant_n_children(bytes).to_i.times do |position|
            byte = child(bytes, position).as_u8
            io.write_byte(byte) unless byte == 0
          end
        end
      end
    end

    def run(requests : Array(MountRequest), cancellable : Gio::Cancellable, &finished : Array(String) -> Nil) : Nil
      return finished.call([] of String) if requests.empty? || cancellable.is_cancelled
      MountDBus.connect(cancellable) do |result|
        connection = nil
        begin
          connection = MountDBus.finish_connect(result)
        rescue ex
          finished.call([error_text(ex)])
        end
        process_next(connection, requests, 0, [] of String, cancellable, finished) if connection
      end
    end

    private def process_next(connection : Gio::DBusConnection, requests : Array(MountRequest), index : Int32, errors : Array(String), cancellable : Gio::Cancellable, finished : Proc(Array(String), Nil)) : Nil
      return finished.call(errors) if index >= requests.size || cancellable.is_cancelled
      request = requests[index]
      path = MountLogic.object_path(request.disk.source)
      parameters = GLib::Variant.parse("('org.freedesktop.UDisks2.Filesystem',)")
      # Re-read current mount points before each operation, including after any
      # preceding authorization dialog or partial success in a batch.
      MountDBus.call(connection, path, "org.freedesktop.DBus.Properties", "GetAll", parameters, cancellable) do |result|
        points = nil
        begin
          reply = connection.call_finish(result)
          points = mount_points(child(reply, 0))
          if !MountLogic.eligible?(request.disk) || MountLogic.protected?(points)
            raise translate("This filesystem cannot be mounted or unmounted here.")
          end
        rescue ex
          errors << "#{request.disk.source}: #{error_text(ex)}"
        end
        if points && (request.action.mount? == points.empty?) && !MountLogic.protected?(points) && MountLogic.eligible?(request.disk)
          method = request.action.mount? ? "Mount" : "Unmount"
          # No force or no-user-interaction flags: UDisks/polkit provides the
          # normal system authorization flow and rejects busy filesystems.
          options = GLib::Variant.parse("(@a{sv} {},)")
          MountDBus.call(connection, path, "org.freedesktop.UDisks2.Filesystem", method, options, cancellable) do |operation_result|
            dismissed = false
            begin
              connection.call_finish(operation_result)
            rescue ex
              errors << "#{request.disk.source}: #{error_text(ex)}"
              dismissed = ex.message.to_s.includes?("org.freedesktop.UDisks2.Error.NotAuthorizedDismissed")
            end
            if dismissed
              # Do not immediately open another authorization dialog after the
              # user explicitly dismissed the current one.
              finished.call(errors)
            else
              process_next(connection, requests, index + 1, errors, cancellable, finished)
            end
          end
        else
          process_next(connection, requests, index + 1, errors, cancellable, finished)
        end
      end
    end
  end
end
