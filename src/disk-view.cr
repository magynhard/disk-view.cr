require "libadwaita"
require "./i18n"
require "./metadata"
require "./disks"
require "./window"

module DiskView
  # Adwaita's default color scheme follows the system, including live changes.
  class App < Adw::Application
    def initialize
      I18n.setup
      super(application_id: APP_ID, flags: Gio::ApplicationFlags::None)
      RESOURCE._register
    end

    @[GObject::Virtual]
    def activate
      Gtk::IconTheme.for_display(Gdk::Display.default.not_nil!).add_resource_path("/de/magynhard/DiskView/icons")
      Gtk::Window.default_icon_name = APP_ID
      window = active_window || Window.new(self)
      window.present
    end
  end
end

exit(DiskView::App.new.run)
