module DiskView::Styles
  CSS = {{read_file("#{__DIR__}/../data/style.css")}}

  def self.install(display : Gdk::Display) : Nil
    provider = Gtk::CssProvider.new
    provider.load_from_string(CSS)
    Gtk::StyleContext.add_provider_for_display(display, provider, Gtk::STYLE_PROVIDER_PRIORITY_APPLICATION.to_u32)
  end
end
